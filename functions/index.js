const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');

// Inicializar Firebase Admin SDK
admin.initializeApp();

// ===== CONFIGURACIÓN =====
const NOTIFICATION_COOLDOWN = 5000;  // Esperar 5s antes de enviar duplicadas
const MAX_FCM_TOKENS_PER_USER = 10;  // Máximo de dispositivos por usuario
const PSK_SECRET = 'wilobu_psk_secret_2025';  // Pre-shared key para auth

// ===== CLOUD FUNCTION: HEARTBEAT (HTTP) =====
/**
 * Recibe heartbeat del firmware y actualiza status/ubicación en Firestore
 * Endpoint: https://us-central1-wilobu-d21b2.cloudfunctions.net/heartbeat
 */
exports.heartbeat = functions.https.onRequest(async (req, res) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    if (req.method === 'OPTIONS') {
        res.set('Access-Control-Allow-Methods', 'POST');
        res.set('Access-Control-Allow-Headers', 'Content-Type');
        return res.status(204).send('');
    }
    
    if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
    }
    
    try {
        const { deviceId, ownerUid, auth, lastLocation, status } = req.body;
        
        // Validar campos requeridos
        if (!deviceId || !ownerUid) {
            return res.status(400).json({ error: 'deviceId and ownerUid required' });
        }
        
        // Validar auth PSK
        if (auth && auth.mode === 'psk') {
            const { ts, nonce, sig } = auth;
            const canonical = `${deviceId}|${ownerUid}|${ts}|${nonce}`;
            const expected = crypto.createHmac('sha256', PSK_SECRET).update(canonical).digest('hex');
            if (sig !== expected) {
                console.warn('[HEARTBEAT] Invalid signature');
                return res.status(401).json({ error: 'Invalid auth' });
            }
        }
        
        // Referencia a documento del dispositivo
        const deviceRef = admin.firestore()
            .collection('users').doc(ownerUid)
            .collection('devices').doc(deviceId);

        const deviceDoc = await deviceRef.get();

        // Si no existe el documento, devolver 410 - NO crear automáticamente
        // Solo la app debe crear documentos post-vinculación para evitar duplicados
        if (!deviceDoc.exists) {
            console.warn(`[HEARTBEAT] ${deviceId} no existe -> 410 device_not_found`);
            return res.status(410).json({ success: false, cmd_reset: true, error: 'device_not_found' });
        }

        const current = deviceDoc.data() || {};

        // Si el owner no coincide, forzar reset
        if (current.ownerUid && current.ownerUid !== ownerUid) {
            console.warn(`[HEARTBEAT] owner mismatch doc=${current.ownerUid} req=${ownerUid}`);
            return res.status(401).json({ success: false, cmd_reset: true, error: 'owner_mismatch' });
        }

        // Si está marcado como desprovisionado o con cmd_reset, forzar reset
        if (current.provisioned === false || current.cmd_reset === true) {
            console.warn(`[HEARTBEAT] ${deviceId} marcado para reset (provisioned=${current.provisioned}, cmd_reset=${current.cmd_reset}) -> 410`);
            try {
                await deviceRef.delete();
                console.log(`[HEARTBEAT] ${deviceId} borrado tras cmd_reset/provisioned=false`);
            } catch (delErr) {
                console.warn(`[HEARTBEAT] No se pudo borrar ${deviceId}:`, delErr);
            }
            return res.status(410).json({ success: false, cmd_reset: true, error: 'device_deprovisioned' });
        }

        const cmdReset = current.cmd_reset === true;

        // Construir update
        const update = {
            status: status || 'online',
            lastSeen: admin.firestore.FieldValue.serverTimestamp()
        };
        
        // Agregar ubicación si viene
        if (lastLocation && lastLocation.lat && lastLocation.lng) {
            update.lastLocation = {
                geopoint: new admin.firestore.GeoPoint(lastLocation.lat, lastLocation.lng),
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            };
        }
        
        // Actualizar documento existente
        try {
            await deviceRef.update(update);
            console.log(`[HEARTBEAT] ✓ ${deviceId} updated`);
        } catch (updateErr) {
            // Si el doc fue borrado entre el .get() y el .update(), devolver 410
            if (updateErr.code === 'NOT_FOUND' || updateErr.code === 5) {
                console.warn(`[HEARTBEAT] ${deviceId} borrado durante update -> 410`);
                return res.status(410).json({ success: false, cmd_reset: true, error: 'device_deleted' });
            }
            throw updateErr; // Re-lanzar otros errores
        }
        
        // Responder con cmd_reset si está activo
        return res.status(200).json({ success: true, cmd_reset: cmdReset });
        
    } catch (error) {
        console.error('[HEARTBEAT] Error:', error);
        return res.status(500).json({ error: error.message });
    }
});

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
    
    // ===== OBTENER NOMBRE DEL DUEÑO DEL DISPOSITIVO =====
    let ownerName = 'Usuario';
    try {
        const ownerDoc = await admin.firestore()
            .collection('users')
            .doc(userId)
            .get();
        
        if (ownerDoc.exists) {
            const ownerData = ownerDoc.data();
            ownerName = ownerData.name || ownerData.displayName || ownerData.email || 'Usuario';
            console.log(`[PROCESSING] Dueño del dispositivo: ${ownerName}`);
        }
    } catch (err) {
        console.warn('[PROCESSING] Error obteniendo nombre del dueño:', err);
    }
    
    // Enriquecer deviceData con info del dueño
    deviceData.ownerName = ownerName;
    deviceData.ownerUid = userId;
    deviceData.deviceId = deviceId;
    
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
    
    // ===== GUARDAR EN alertHistory DEL DISPOSITIVO =====
    // Reutilizamos la variable 'location' que ya existe arriba
    let alertGeopoint = null;
    if (location && location.geopoint) {
        alertGeopoint = location.geopoint;
    } else if (location && location.latitude && location.longitude) {
        alertGeopoint = new admin.firestore.GeoPoint(location.latitude, location.longitude);
    }
    
    await admin.firestore()
        .collection('users').doc(userId)
        .collection('devices').doc(deviceId)
        .collection('alertHistory')
        .add({
            type: sosStatus.replace('sos_', ''),
            sosType: sosStatus,
            message: sosMessage,
            location: alertGeopoint,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            deviceId: deviceId,
            ownerUid: userId,
            ownerName: deviceData.ownerName || 'Usuario',
            notificationsSent: successCount,
            notificationsFailed: failureCount,
            contactsNotified: emergencyContacts.map(c => ({
                uid: c.uid,
                name: c.name || 'Contacto'
            }))
        });
    
    console.log(`[PROCESSING] ✓ Alerta guardada en alertHistory del dispositivo ${deviceId}`);
    
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
        
        // ===== GUARDAR ALERTA EN receivedAlerts DEL CONTACTO =====
        const location = deviceData.lastLocation || null;
        let geopoint = null;
        if (location && location.geopoint) {
            geopoint = location.geopoint;
        } else if (location && location.latitude && location.longitude) {
            geopoint = new admin.firestore.GeoPoint(location.latitude, location.longitude);
        }
        
        await admin.firestore()
            .collection('users').doc(contactUid)
            .collection('receivedAlerts')
            .add({
                fromDeviceId: deviceData.deviceId || 'unknown',
                fromUserName: deviceData.ownerName || 'Usuario',
                fromUserId: deviceData.ownerUid || null,
                type: config.type.toLowerCase(),
                sosType: dataPayload.sosType,
                message: sosMessage,
                location: geopoint,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                acknowledged: false,
            });
        
        console.log(`[CONTACT] ✓ Alerta guardada en receivedAlerts de ${contactName}`);
        
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

// ===== CLOUD FUNCTION: AGREGAR USUARIO DE PRUEBA COMO CONTACTO =====
/**
 * Agrega al usuario de prueba como contacto de emergencia de todos los dispositivos
 * Solo ejecutar una vez para configuración inicial
 * Endpoint: https://us-central1-wilobu-d21b2.cloudfunctions.net/addTestUserAsContact
 */
exports.addTestUserAsContact = functions.https.onRequest(async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');
    if (req.method === 'OPTIONS') {
        res.set('Access-Control-Allow-Methods', 'POST');
        res.set('Access-Control-Allow-Headers', 'Content-Type');
        return res.status(204).send('');
    }
    
    try {
        const TEST_USER_EMAIL = 'wilobu.test@gmail.com';
        const TEST_USER_NAME = 'Usuario Wilobu Test';
        
        // Buscar UID del usuario de prueba
        const usersRef = admin.firestore().collection('users');
        const testUserQuery = await usersRef.where('email', '==', TEST_USER_EMAIL).limit(1).get();
        
        if (testUserQuery.empty) {
            return res.status(404).json({ error: 'Usuario de prueba no encontrado' });
        }
        
        const testUserDoc = testUserQuery.docs[0];
        const testUserUid = testUserDoc.id;
        
        console.log(`[ADD-TEST-CONTACT] Usuario de prueba: ${testUserUid}`);
        
        // Contacto de prueba a agregar
        const testContact = {
            uid: testUserUid,
            name: TEST_USER_NAME,
            relation: 'Soporte Wilobu',
            phone: '+56900000000'
        };
        
        // Obtener todos los usuarios
        const allUsers = await usersRef.get();
        let devicesUpdated = 0;
        
        for (const userDoc of allUsers.docs) {
            // Saltar el usuario de prueba (no se agrega a sí mismo)
            if (userDoc.id === testUserUid) continue;
            
            // Obtener dispositivos del usuario
            const devicesRef = usersRef.doc(userDoc.id).collection('devices');
            const devices = await devicesRef.get();
            
            for (const deviceDoc of devices.docs) {
                const data = deviceDoc.data();
                const contacts = data.emergencyContacts || [];
                
                // Verificar si ya está agregado
                const alreadyAdded = contacts.some(c => c.uid === testUserUid);
                
                if (!alreadyAdded) {
                    await deviceDoc.ref.update({
                        emergencyContacts: admin.firestore.FieldValue.arrayUnion(testContact)
                    });
                    devicesUpdated++;
                    console.log(`[ADD-TEST-CONTACT] Agregado a ${userDoc.id}/${deviceDoc.id}`);
                }
            }
        }
        
        return res.status(200).json({ 
            success: true, 
            testUserUid,
            devicesUpdated,
            message: `Usuario de prueba agregado a ${devicesUpdated} dispositivos`
        });
        
    } catch (error) {
        console.error('[ADD-TEST-CONTACT] Error:', error);
        return res.status(500).json({ error: error.message });
    }
});

// ===== CLOUD FUNCTION: CLEANUP UNPROVISIONNED DEVICES (Scheduled) =====
/**
 * Se ejecuta diariamente para limpiar dispositivos que se han desaprovisionado
 * y no han hecho heartbeat en 24 horas (presuntamente ya hicieron reset)
 */
exports.cleanupUnprovisionedDevices = functions.pubsub
    .schedule('every 24 hours')
    .onRun(async (context) => {
        try {
            const now = new Date();
            const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
            
            let totalDeleted = 0;
            
            // Iterar todos los usuarios
            const usersSnapshot = await admin.firestore().collection('users').get();
            
            for (const userDoc of usersSnapshot.docs) {
                // Buscar dispositivos no aprovisionados y con reset_requested_at > 24h
                const devicesSnapshot = await userDoc.ref.collection('devices')
                    .where('provisioned', '==', false)
                    .where('reset_requested_at', '<', oneDayAgo)
                    .get();
                
                for (const deviceDoc of devicesSnapshot.docs) {
                    await deviceDoc.ref.delete();
                    totalDeleted++;
                    console.log(`[CLEANUP] Eliminado: ${userDoc.id}/${deviceDoc.id}`);
                }
            }
            
            console.log(`[CLEANUP] Total dispositivos eliminados: ${totalDeleted}`);
            return { success: true, deleted: totalDeleted };
            
        } catch (error) {
            console.error('[CLEANUP] Error:', error);
            return { error: error.message };
        }
    });

// ===== NOTIFICACIONES DE VINCULACIÓN / DESVINCULACIÓN =====
async function sendOwnerNotification(userId, title, body) {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) return;
    const tokens = userDoc.data().fcmTokens || [];
    if (!tokens.length) return;

    const message = {
        notification: { title, body },
        tokens,
        data: { type: 'device_event' }
    };

    const resp = await admin.messaging().sendMulticast(message);
    const invalid = [];
    resp.responses.forEach((r, idx) => {
        if (!r.success && r.error && (
            r.error.code === 'messaging/invalid-registration-token' ||
            r.error.code === 'messaging/registration-token-not-registered'
        )) {
            invalid.push(tokens[idx]);
        }
    });
    if (invalid.length) {
        await userDoc.ref.update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalid)
        });
    }
}

exports.onDeviceLinked = functions.firestore
    .document('users/{userId}/devices/{deviceId}')
    .onCreate(async (snap, context) => {
        const { userId, deviceId } = context.params;
        const name = snap.data().name || deviceId;
        await sendOwnerNotification(
            userId,
            'Wilobu vinculado',
            `Tu dispositivo ${name} se vinculó correctamente.`
        );
        return null;
    });

exports.onDeviceUnlinked = functions.firestore
    .document('users/{userId}/devices/{deviceId}')
    .onDelete(async (snap, context) => {
        const { userId, deviceId } = context.params;
        const name = snap.data()?.name || deviceId;
        await sendOwnerNotification(
            userId,
            'Wilobu desvinculado',
            `El dispositivo ${name} fue desvinculado.`
        );
        return null;
    });

// ===== CLOUD FUNCTION: CHECK DEVICE STATUS (HTTP) =====
/**
 * Verifica si un dispositivo existe en Firestore y devuelve su ownerUid
 * Usado para auto-recuperación cuando el firmware pierde configuración local
 * Endpoint: https://us-central1-wilobu-d21b2.cloudfunctions.net/checkDeviceStatus
 */
exports.checkDeviceStatus = functions.https.onRequest(async (req, res) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    if (req.method === 'OPTIONS') {
        res.set('Access-Control-Allow-Methods', 'POST');
        res.set('Access-Control-Allow-Headers', 'Content-Type');
        return res.status(204).send('');
    }
    
    if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
    }
    
    try {
        // Log para debugging
        console.log('[CHECK_DEVICE] Headers:', req.headers);
        console.log('[CHECK_DEVICE] Body type:', typeof req.body);
        console.log('[CHECK_DEVICE] Raw body:', req.body);
        
        // Intentar parsear de varias formas
        let deviceId = req.body?.deviceId;
        
        // Si req.body es string (rawBody), intentar parsearlo
        if (typeof req.body === 'string') {
            try {
                const parsed = JSON.parse(req.body);
                deviceId = parsed.deviceId;
            } catch (e) {
                console.log('[CHECK_DEVICE] Failed to parse body as JSON');
            }
        }
        
        // Si aún no tenemos deviceId, buscar en query params como fallback
        if (!deviceId && req.query.deviceId) {
            deviceId = req.query.deviceId;
        }
        
        // Validar campo requerido
        if (!deviceId) {
            return res.status(400).json({ error: 'deviceId required' });
        }
        
        console.log('[CHECK_DEVICE] Buscando dispositivo:', deviceId);
        console.log('[CHECK_DEVICE] Query mode: docId then field deviceId');
        
        // Buscar el dispositivo; preferimos docId para evitar fallar si falta el campo deviceId
        const byIdSnapshot = await admin.firestore()
            .collectionGroup('devices')
            .where(admin.firestore.FieldPath.documentId(), '==', deviceId)
            .limit(1)
            .get();

        let deviceDoc = byIdSnapshot.docs[0];

        // Fallback: buscar por campo deviceId si no lo encontramos por docId
        if (!deviceDoc) {
            const devicesSnapshot = await admin.firestore()
                .collectionGroup('devices')
                .where('deviceId', '==', deviceId)
                .limit(1)
                .get();
            deviceDoc = devicesSnapshot.docs.find(doc => doc.id === deviceId) || devicesSnapshot.docs[0];
        }
        
        if (!deviceDoc) {
            console.log('[CHECK_DEVICE] Dispositivo no encontrado:', deviceId);
            return res.status(404).json({ 
                error: 'Device not found',
                message: 'Este dispositivo no está vinculado a ninguna cuenta'
            });
        }
        
        const deviceData = deviceDoc.data();
        const ownerUid = deviceData.ownerUid;
        
        if (!ownerUid) {
            console.log('[CHECK_DEVICE] Dispositivo sin ownerUid:', deviceId);
            return res.status(404).json({ 
                error: 'Invalid device data',
                message: 'El dispositivo no tiene un propietario asignado'
            });
        }
        
        console.log('[CHECK_DEVICE] ✓ Dispositivo encontrado:', deviceId, '-> Owner:', ownerUid);
        
        // Devolver ownerUid para que el firmware se auto-aprovisione
        return res.status(200).json({
            success: true,
            deviceId: deviceId,
            ownerUid: ownerUid,
            message: 'Dispositivo encontrado - auto-aprovisionamiento disponible'
        });
        
    } catch (error) {
        console.error('[CHECK_DEVICE] Error:', error);
        // Devolver 404 en lugar de 500 para evitar loops en firmware cuando simplemente no existe
        return res.status(404).json({ 
            error: 'Device lookup failed',
            message: error.message || 'Not found'
        });
    }
});

module.exports = module.exports;
