const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Inicializar Firebase Admin SDK
admin.initializeApp();

// ===== CONFIGURACIÓN =====
const NOTIFICATION_COOLDOWN = 5000;  // Esperar 5s antes de enviar duplicadas
const MAX_FCM_TOKENS_PER_USER = 10;  // Máximo de dispositivos por usuario

// ===== CLOUD FUNCTION: ALERTA SOS =====
/**
 * Se ejecuta automáticamente cuando cambia el status de un dispositivo
 * Si el status es SOS (sos_general, sos_medica, sos_seguridad):
 * 1. Lee los contactos de emergencia del dispositivo
 * 2. Busca los FCM tokens de cada contacto en Firestore
 * 3. Envía notificaciones push a través de FCM
 * 4. Elimina tokens inválidos automáticamente
 */
exports.onDeviceStatusChange = functions.firestore
    .document('users/{userId}/devices/{deviceId}')
    .onUpdate(async (change, context) => {
        try {
            const before = change.before.data();
            const after = change.after.data();
            const { userId, deviceId } = context.params;
            
            // Validar que los datos existan
            if (!before || !after) {
                console.log('[SOS-HANDLER] Datos incompletos, abortando');
                return null;
            }
            
            const oldStatus = before.status || 'unknown';
            const newStatus = after.status || 'unknown';
            
            // Solo procesar si cambió el status
            if (oldStatus === newStatus) {
                console.log('[SOS-HANDLER] Status sin cambios, ignorando');
                return null;
            }
            
            console.log(`[SOS-HANDLER] Transición: ${oldStatus} → ${newStatus}`);
            
            // Solo procesar alertas SOS
            if (!newStatus.startsWith('sos_')) {
                console.log('[SOS-HANDLER] No es una alerta SOS, ignorando');
                return null;
            }
            
            // Evitar procesamiento duplicado (cooldown)
            const lastProcessed = after.lastSOSProcessed || 0;
            if (Date.now() - lastProcessed < NOTIFICATION_COOLDOWN) {
                console.log('[SOS-HANDLER] Alerta duplicada en cooldown, ignorando');
                return null;
            }
            
            // ===== PROCESAR ALERTA SOS =====
            await processSosAlert(userId, deviceId, newStatus, after);
            
            // Marcar como procesada
            await admin.firestore()
                .collection('users').doc(userId)
                .collection('devices').doc(deviceId)
                .update({
                    lastSOSProcessed: Date.now()
                });
            
            return null;
            
        } catch (error) {
            console.error('[SOS-HANDLER] Error:', error);
            return null;
        }
    });

// ===== PROCESAMIENTO DE ALERTA SOS =====
async function processSosAlert(userId, deviceId, sosStatus, deviceData) {
    console.log(`[PROCESSING] Procesando alerta SOS: ${sosStatus}`);
    
    // Determinar tipo y mensaje de SOS
    const sosConfig = {
        'sos_general': {
            title: '🚨 Alerta de Emergencia',
            type: 'General',
            defaultMessage: 'Se ha activado una alerta de emergencia.'
        },
        'sos_medica': {
            title: '🚑 Alerta Médica',
            type: 'Médica',
            defaultMessage: 'Se ha detectado una emergencia médica. Se requiere asistencia inmediata.'
        },
        'sos_seguridad': {
            title: '⚠️  Alerta de Seguridad',
            type: 'Seguridad',
            defaultMessage: 'Se ha detectado una situación de peligro. Se requiere asistencia.'
        }
    };
    
    const config = sosConfig[sosStatus] || sosConfig['sos_general'];
    
    // Obtener mensajes personalizados del dispositivo
    const sosMessages = deviceData.sosMessages || {};
    const sosMessage = sosMessages[config.type.toLowerCase()] || config.defaultMessage;
    
    // Obtener contactos de emergencia
    const emergencyContacts = deviceData.emergencyContacts || [];
    
    if (emergencyContacts.length === 0) {
        console.log('[PROCESSING] ✗ Sin contactos de emergencia configurados');
        return;
    }
    
    console.log(`[PROCESSING] Notificando a ${emergencyContacts.length} contactos`);
    
    // Obtener información de ubicación
    const location = deviceData.lastLocation || null;
    let locationText = 'Ubicación no disponible';
    let locationMapUrl = null;
    
    if (location && location.latitude && location.longitude) {
        locationText = `Lat: ${location.latitude.toFixed(6)}, Lon: ${location.longitude.toFixed(6)}`;
        locationMapUrl = `https://maps.google.com/?q=${location.latitude},${location.longitude}`;
    }
    
    // Array de promesas para envío paralelo
    const notificationPromises = [];
    
    // Procesar cada contacto de emergencia
    for (const contact of emergencyContacts) {
        const contactUid = contact.uid;
        const contactName = contact.name || 'Contacto';
        
        const promise = sendSOSNotificationToContact(
            contactUid,
            contactName,
            deviceData,
            config,
            sosMessage,
            locationText,
            locationMapUrl
        );
        
        notificationPromises.push(promise);
    }
    
    // Ejecutar todas las notificaciones en paralelo
    const results = await Promise.allSettled(notificationPromises);
    
    // Contar éxitos y fallos
    let successCount = 0;
    let failureCount = 0;
    
    results.forEach((result, index) => {
        if (result.status === 'fulfilled' && result.value.success) {
            successCount++;
        } else {
            failureCount++;
            console.warn(`[PROCESSING] Error en contacto ${index}: ${result.reason || 'unknown error'}`);
        }
    });
    
    console.log(`[PROCESSING] ✓ Resultado: ${successCount} éxitos, ${failureCount} fallos`);
    
    // Guardar estadísticas de notificación
    await admin.firestore()
        .collection('users').doc(userId)
        .collection('devices').doc(deviceId)
        .update({
            lastSosAlert: {
                timestamp: Date.now(),
                type: sosStatus,
                notificationsSent: successCount,
                notificationsFailed: failureCount
            }
        }).catch(err => console.warn('[PROCESSING] Error al guardar estadísticas:', err));
}

// ===== ENVÍO DE NOTIFICACIÓN A UN CONTACTO =====
async function sendSOSNotificationToContact(
    contactUid,
    contactName,
    deviceData,
    config,
    sosMessage,
    locationText,
    locationMapUrl
) {
    try {
        console.log(`[CONTACT] Procesando contacto: ${contactName} (${contactUid})`);
        
        // Obtener documento del contacto
        const contactDoc = await admin.firestore()
            .collection('users')
            .doc(contactUid)
            .get();
        
        if (!contactDoc.exists) {
            console.warn(`[CONTACT] ✗ Contacto ${contactUid} no encontrado en Firestore`);
            return { success: false, error: 'Contact not found' };
        }
        
        const contactData = contactDoc.data();
        const fcmTokens = contactData.fcmTokens || [];
        
        if (fcmTokens.length === 0) {
            console.warn(`[CONTACT] ✗ ${contactName} no tiene tokens FCM registrados`);
            return { success: false, error: 'No FCM tokens' };
        }
        
        console.log(`[CONTACT] ${contactName} tiene ${fcmTokens.length} dispositivos activos`);
        
        // Construir payload de notificación
        const notificationPayload = {
            title: config.title,
            body: sosMessage,
            sound: 'default',
            priority: 'max'
        };
        
        const dataPayload = {
            type: 'sos_alert',
            sosType: config.type.toLowerCase(),
            deviceId: deviceData.deviceId,
            ownerName: contactData.name || 'Usuario',
            location: locationText,
            locationUrl: locationMapUrl || '',
            timestamp: Date.now().toString(),
            urgent: 'true'
        };
        
        // Construir mensaje FCM
        const message = {
            notification: notificationPayload,
            data: dataPayload,
            tokens: fcmTokens,
            android: {
                priority: 'high',
                notification: {
                    sound: 'default',
                    channelId: 'sos_alerts',
                    priority: 'max',
                    visibility: 'public',
                    clickAction: 'FLUTTER_NOTIFICATION_CLICK'
                }
            },
            apns: {
                payload: {
                    aps: {
                        alert: {
                            title: config.title,
                            body: sosMessage
                        },
                        sound: 'default',
                        badge: 1,
                        'interruption-level': 'critical',
                        'content-available': 1
                    }
                }
            },
            webpush: {
                notification: {
                    title: config.title,
                    body: sosMessage,
                    icon: 'https://wilobu.app/icon-192.png',
                    badge: 'https://wilobu.app/badge-72.png',
                    tag: 'sos-alert',
                    requireInteraction: true
                },
                fcmOptions: {
                    link: locationMapUrl || 'https://wilobu.app'
                }
            }
        };
        
        // Enviar notificación multicast
        const response = await admin.messaging().sendMulticast(message);
        
        console.log(`[CONTACT] ✓ ${contactName}: ${response.successCount} éxitos, ${response.failureCount} fallos`);
        
        // Procesar fallos y eliminar tokens inválidos
        if (response.failureCount > 0) {
            const tokensToRemove = [];
            
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    console.warn(`[CONTACT]   Token ${idx} falló: ${resp.error.code}`);
                    
                    // Eliminar tokens inválidos
                    if (resp.error.code === 'messaging/invalid-registration-token' ||
                        resp.error.code === 'messaging/registration-token-not-registered') {
                        tokensToRemove.push(fcmTokens[idx]);
                    }
                }
            });
            
            // Actualizar lista de tokens si hay que eliminar algunos
            if (tokensToRemove.length > 0) {
                console.log(`[CONTACT] Eliminando ${tokensToRemove.length} tokens inválidos`);
                
                await admin.firestore()
                    .collection('users')
                    .doc(contactUid)
                    .update({
                        fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToRemove)
                    });
            }
        }
        
        return { success: response.successCount > 0 };
        
    } catch (error) {
        console.error(`[CONTACT] ✗ Error procesando ${contactName}:`, error);
        return { success: false, error: error.message };
    }
}

// ===== CALLABLE: REGISTRAR TOKEN FCM =====
/**
 * Función llamable desde la app para registrar el token FCM del usuario
 * Se ejecuta cuando el usuario inicia sesión
 * 
 * Uso desde Flutter:
 * final result = await FirebaseFunctions.instance
 *     .httpsCallable('registerFcmToken')
 *     .call({'token': fcmToken});
 */
exports.registerFcmToken = functions.https.onCall(async (data, context) => {
    try {
        // Verificar que el usuario esté autenticado
        if (!context.auth) {
            throw new functions.https.HttpsError(
                'unauthenticated',
                'Usuario no autenticado'
            );
        }
        
        const userId = context.auth.uid;
        const fcmToken = data.token;
        
        // Validar parámetros
        if (!fcmToken || typeof fcmToken !== 'string') {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Token FCM inválido'
            );
        }
        
        // Obtener documento del usuario
        const userDoc = await admin.firestore()
            .collection('users')
            .doc(userId)
            .get();
        
        if (!userDoc.exists) {
            console.warn(`[FCM-REGISTER] Usuario ${userId} no existe`);
            return { success: false, error: 'User not found' };
        }
        
        const userData = userDoc.data();
        const fcmTokens = userData.fcmTokens || [];
        
        // Evitar tokens duplicados
        if (fcmTokens.includes(fcmToken)) {
            console.log(`[FCM-REGISTER] Token duplicado para ${userId}`);
            return { success: true, duplicate: true };
        }
        
        // Limitar cantidad de tokens (evitar acumulación)
        let updatedTokens = [...fcmTokens, fcmToken];
        if (updatedTokens.length > MAX_FCM_TOKENS_PER_USER) {
            updatedTokens = updatedTokens.slice(-MAX_FCM_TOKENS_PER_USER);
        }
        
        // Guardar token
        await admin.firestore()
            .collection('users')
            .doc(userId)
            .update({
                fcmTokens: updatedTokens,
                lastTokenUpdate: admin.firestore.FieldValue.serverTimestamp()
            });
        
        console.log(`[FCM-REGISTER] ✓ Token registrado para ${userId} (Total: ${updatedTokens.length})`);
        
        return {
            success: true,
            message: 'Token registrado correctamente',
            totalTokens: updatedTokens.length
        };
        
    } catch (error) {
        console.error('[FCM-REGISTER] Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// ===== CALLABLE: DESREGISTRAR TOKEN FCM =====
/**
 * Función para eliminar un token FCM (logout)
 */
exports.unregisterFcmToken = functions.https.onCall(async (data, context) => {
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'No autenticado');
        }
        
        const userId = context.auth.uid;
        const fcmToken = data.token;
        
        if (!fcmToken) {
            throw new functions.https.HttpsError('invalid-argument', 'Token requerido');
        }
        
        // Eliminar token
        await admin.firestore()
            .collection('users')
            .doc(userId)
            .update({
                fcmTokens: admin.firestore.FieldValue.arrayRemove(fcmToken)
            });
        
        console.log(`[FCM-UNREGISTER] ✓ Token eliminado para ${userId}`);
        
        return { success: true };
        
    } catch (error) {
        console.error('[FCM-UNREGISTER] Error:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

module.exports = module.exports;
