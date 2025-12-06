/**
 * Cloudflare Worker - Proxy de Seguridad para Wilobu
 * 
 * Recibe solicitudes HTTP del hardware Tier B/C (A7670SA)
 * y las retransmite como HTTPS (TLS 1.2) a Firebase Firestore.
 * 
 * Arquitectura:
 * [Hardware (HTTP)] → [Cloudflare Worker (HTTPS)] → [Firebase Firestore]
 * 
 * Funciones:
 * - Validar integridad de datos del dispositivo
 * - Cifrar comunicación hacia Firebase (TLS 1.2)
 * - Proteger credenciales de API
 * - Registrar todas las transacciones
 * - Redirigir eventos SOS a Cloud Functions
 */

// ===== CONFIGURACIÓN =====
// Obtener estos valores de Firebase Console
const FIREBASE_PROJECT_ID = 'wilobu-d21b2';
const FIREBASE_API_KEY = '';  // TODO: Obtener de Firebase Console
const FIREBASE_CUSTOM_DOMAIN = 'firestore.googleapis.com';

// ===== CONSTANTES =====
const ALLOWED_STATUS = ['online', 'sos_general', 'sos_medica', 'sos_seguridad', 'offline'];
const REQUEST_TIMEOUT = 30000;  // 30 segundos
const MAX_PAYLOAD_SIZE = 5120;  // 5 KB

// ===== LISTENER PRINCIPAL =====
addEventListener('fetch', event => {
    event.respondWith(handleRequest(event.request));
});

// ===== MANEJADOR DE SOLICITUDES =====
async function handleRequest(request) {
    // Validar método HTTP (solo POST)
    if (request.method !== 'POST') {
        return errorResponse(405, 'Method not allowed. Use POST');
    }
    
    try {
        // Obtener URL de la ruta
        const url = new URL(request.url);
        const pathname = url.pathname;
        
        // Logs y debugging
        console.log(`[WORKER] ${request.method} ${pathname}`);
        console.log(`[WORKER] Content-Length: ${request.headers.get('content-length')} bytes`);
        
        // Validar tamaño de payload
        const contentLength = parseInt(request.headers.get('content-length') || '0');
        if (contentLength > MAX_PAYLOAD_SIZE) {
            return errorResponse(413, `Payload too large. Max: ${MAX_PAYLOAD_SIZE} bytes`);
        }
        
        // Leer y parsear JSON
        let payload;
        try {
            payload = await request.json();
        } catch (e) {
            return errorResponse(400, 'Invalid JSON: ' + e.message);
        }
        
        // Validar campos requeridos
        const validation = validatePayload(payload);
        if (!validation.valid) {
            return errorResponse(400, 'Validation error: ' + validation.error);
        }
        
        const { deviceId, ownerUid, status, sosType, lastLocation } = payload;
        
        console.log(`[WORKER] Device: ${deviceId}, Owner: ${ownerUid}, Status: ${status}`);
        
        // Construir documento de Firestore (formato API v1)
        const firestoreDoc = buildFirestoreDocument(payload);
        
        // Enviar a Firestore con HTTPS (TLS 1.2)
        const updateResult = await updateFirestore(ownerUid, deviceId, firestoreDoc);
        
        if (!updateResult.success) {
            return errorResponse(updateResult.status || 500, updateResult.error);
        }
        
        // Si es una alerta SOS, disparar Cloud Function
        if (status && status.startsWith('sos_')) {
            console.log(`[WORKER] Disparando alerta SOS: ${sosType}`);
            // TODO: Llamar a Cloud Function para notificaciones FCM
            // await triggerSOSNotification(ownerUid, deviceId, sosType, lastLocation);
        }
        
        // Respuesta exitosa
        return successResponse({
            success: true,
            message: 'Device state updated',
            deviceId: deviceId,
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('[WORKER] Error no controlado:', error);
        return errorResponse(500, 'Internal server error: ' + error.message);
    }
}

// ===== VALIDACIÓN DE PAYLOAD =====
function validatePayload(payload) {
    // Campos requeridos
    if (!payload.deviceId || typeof payload.deviceId !== 'string') {
        return { valid: false, error: 'deviceId must be a non-empty string' };
    }
    
    if (!payload.ownerUid || typeof payload.ownerUid !== 'string') {
        return { valid: false, error: 'ownerUid must be a non-empty string' };
    }
    
    if (payload.deviceId.length < 10) {
        return { valid: false, error: 'deviceId too short' };
    }
    
    if (payload.ownerUid.length < 10) {
        return { valid: false, error: 'ownerUid too short' };
    }
    
    // Status validación
    if (payload.status && !ALLOWED_STATUS.includes(payload.status)) {
        return { valid: false, error: `Invalid status: ${payload.status}` };
    }
    
    // Validar ubicación si existe
    if (payload.lastLocation) {
        if (typeof payload.lastLocation.latitude !== 'number' || 
            typeof payload.lastLocation.longitude !== 'number') {
            return { valid: false, error: 'Invalid location coordinates' };
        }
        
        // Rango válido para coordenadas GPS
        if (payload.lastLocation.latitude < -90 || payload.lastLocation.latitude > 90) {
            return { valid: false, error: 'Latitude out of range' };
        }
        if (payload.lastLocation.longitude < -180 || payload.lastLocation.longitude > 180) {
            return { valid: false, error: 'Longitude out of range' };
        }
    }
    
    return { valid: true };
}

// ===== CONSTRUCCIÓN DE DOCUMENTO FIRESTORE =====
function buildFirestoreDocument(payload) {
    const now = new Date().toISOString();
    
    const doc = {
        fields: {
            deviceId: { stringValue: payload.deviceId },
            ownerUid: { stringValue: payload.ownerUid },
            status: { stringValue: payload.status || 'online' },
            updatedAt: { timestampValue: now }
        }
    };
    
    // Agregar timestamp si no existe
    if (payload.timestamp) {
        doc.fields.timestamp = { integerValue: payload.timestamp.toString() };
    }
    
    // Agregar ubicación si existe
    if (payload.lastLocation) {
        doc.fields.lastLocation = {
            mapValue: {
                fields: {
                    latitude: { doubleValue: payload.lastLocation.latitude },
                    longitude: { doubleValue: payload.lastLocation.longitude },
                    accuracy: { doubleValue: payload.lastLocation.accuracy || 999.0 },
                    timestamp: { timestampValue: now }
                }
            }
        };
    }
    
    // Agregar tipo SOS si es aplicable
    if (payload.sosType) {
        doc.fields.sosType = { stringValue: payload.sosType };
    }
    
    return doc;
}

// ===== ACTUALIZAR FIRESTORE =====
async function updateFirestore(ownerUid, deviceId, doc) {
    // Validar que tenemos credenciales
    if (!FIREBASE_API_KEY) {
        console.error('[WORKER] ERROR: FIREBASE_API_KEY no configurada');
        return {
            success: false,
            error: 'Firebase credentials not configured',
            status: 500
        };
    }
    
    // Construir URL de Firestore REST API
    const firestoreUrl = `https://${FIREBASE_CUSTOM_DOMAIN}/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${ownerUid}/devices/${deviceId}?key=${FIREBASE_API_KEY}`;
    
    console.log(`[FIRESTORE] PATCH ${firestoreUrl}`);
    
    try {
        const response = await fetch(firestoreUrl, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'Wilobu-Proxy/1.0'
            },
            body: JSON.stringify(doc),
            timeout: REQUEST_TIMEOUT
        });
        
        // Logging de respuesta
        console.log(`[FIRESTORE] Status: ${response.status}`);
        
        if (!response.ok) {
            const errorText = await response.text();
            console.error('[FIRESTORE] Error:', errorText);
            
            return {
                success: false,
                error: `Firestore error (${response.status}): ${errorText}`,
                status: response.status
            };
        }
        
        const responseData = await response.json();
        console.log('[FIRESTORE] ✓ Documento actualizado');
        
        return {
            success: true,
            data: responseData
        };
        
    } catch (error) {
        console.error('[FIRESTORE] Exception:', error);
        return {
            success: false,
            error: 'Firestore request failed: ' + error.message,
            status: 503
        };
    }
}

// ===== DISPARADOR DE NOTIFICACIÓN SOS =====
async function triggerSOSNotification(ownerUid, deviceId, sosType, location) {
    // TODO: Implementar llamada a Cloud Function
    // La Cloud Function se encarga de:
    // 1. Leer emergencyContacts del dispositivo en Firestore
    // 2. Buscar fcmTokens de cada contacto en la colección users
    // 3. Enviar notificaciones multicast a través de FCM
    
    console.log(`[NOTIFICATION] SOS ${sosType} para contactos de emergencia`);
    // Implementar cuando Cloud Functions esté lista
}

// ===== RESPUESTAS =====
function successResponse(data) {
    return new Response(JSON.stringify(data), {
        status: 200,
        headers: {
            'Content-Type': 'application/json',
            'X-Powered-By': 'Wilobu-Proxy/1.0',
            'Cache-Control': 'no-cache'
        }
    });
}

function errorResponse(status, message) {
    return new Response(JSON.stringify({
        success: false,
        error: message,
        timestamp: new Date().toISOString()
    }), {
        status: status,
        headers: {
            'Content-Type': 'application/json',
            'X-Powered-By': 'Wilobu-Proxy/1.0',
            'Cache-Control': 'no-cache'
        }
    });
}
    });

  } catch (error) {
    console.error('[PROXY] Error:', error);
    
    return new Response(JSON.stringify({
      error: 'Internal server error',
      message: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
