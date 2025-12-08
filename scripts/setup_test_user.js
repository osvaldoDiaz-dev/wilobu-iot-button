// Script para configurar el usuario de prueba con ecosistema completo
// Ejecutar con: node scripts/setup_test_user.js

const admin = require('firebase-admin');

// Configuración
const TEST_USER = {
  uid: 'rEIrSQPTHIel9ySQWX2cWlL6HGX2',
  email: 'wilobu.test@gmail.com',
  displayName: 'Usuario Test Wilobu'
};

const TEST_DEVICE = {
  id: '781C3CB994FC',
  status: 'online'
};

// Ubicación hardcodeada: Antofagasta, Chile
const LOCATION = { lat: -23.6509, lng: -70.3975 };

// Contactos de emergencia de prueba
const EMERGENCY_CONTACTS = [
  { uid: 'contact_familia_001', name: 'María García', relation: 'Familiar', email: 'maria.garcia@test.com' },
  { uid: 'contact_amigo_002', name: 'Carlos López', relation: 'Amigo', email: 'carlos.lopez@test.com' },
  { uid: 'contact_vecino_003', name: 'Ana Martínez', relation: 'Vecino', email: 'ana.martinez@test.com' },
];

// Historial de alertas enviadas
const SENT_ALERTS = [
  { type: 'sos_general', timestamp: new Date('2025-12-01T10:30:00'), resolved: true },
  { type: 'sos_medica', timestamp: new Date('2025-12-03T15:45:00'), resolved: true },
  { type: 'sos_seguridad', timestamp: new Date('2025-12-05T22:10:00'), resolved: false },
];

// Historial de alertas recibidas (como contacto de otro usuario)
const RECEIVED_ALERTS = [
  { fromName: 'Pedro Sánchez', type: 'sos_general', timestamp: new Date('2025-11-28T08:15:00'), acknowledged: true },
  { fromName: 'Laura Rodríguez', type: 'sos_medica', timestamp: new Date('2025-12-02T14:20:00'), acknowledged: false },
];

async function setupTestUser() {
  // Inicializar Firebase Admin
  admin.initializeApp({
    projectId: 'wilobu-d21b2'
  });
  
  const db = admin.firestore();
  const userRef = db.collection('users').doc(TEST_USER.uid);
  const deviceRef = userRef.collection('devices').doc(TEST_DEVICE.id);
  
  console.log('🔧 Configurando usuario de prueba...\n');
  
  // 1. Crear/actualizar documento del usuario
  console.log('1. Creando documento de usuario...');
  await userRef.set({
    email: TEST_USER.email,
    name: TEST_USER.displayName,
    displayName: TEST_USER.displayName,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    fcmTokens: []
  }, { merge: true });
  console.log('   ✓ Usuario configurado\n');
  
  // 2. Crear contactos de emergencia como usuarios
  console.log('2. Creando contactos de emergencia...');
  for (const contact of EMERGENCY_CONTACTS) {
    await db.collection('users').doc(contact.uid).set({
      email: contact.email,
      name: contact.name,
      displayName: contact.name,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      fcmTokens: []
    }, { merge: true });
    console.log(`   ✓ ${contact.name} (${contact.email})`);
  }
  console.log('');
  
  // 3. Configurar dispositivo con contactos
  console.log('3. Configurando dispositivo...');
  await deviceRef.set({
    ownerUid: TEST_USER.uid,
    ownerName: TEST_USER.displayName,
    status: TEST_DEVICE.status,
    lastSeen: admin.firestore.FieldValue.serverTimestamp(),
    lastLocation: {
      geopoint: new admin.firestore.GeoPoint(LOCATION.lat, LOCATION.lng),
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    },
    emergencyContacts: EMERGENCY_CONTACTS.map(c => ({
      uid: c.uid,
      name: c.name,
      relation: c.relation
    })),
    viewerUids: ['contact_familia_001', 'contact_amigo_002'],
    sosMessages: {
      general: '¡Necesito ayuda urgente!',
      medica: 'Emergencia médica, por favor llamen a una ambulancia',
      seguridad: 'Me siento en peligro, necesito ayuda inmediata'
    }
    ,
    viewers: [
      { uid: 'viewer_001', name: 'Sofía Viewer' },
      { uid: 'viewer_002', name: 'Luis Observador' }
    ]
  }, { merge: true });
  console.log(`   ✓ Dispositivo ${TEST_DEVICE.id} configurado con viewerUids\n`);
  
  // 4. Crear historial de alertas enviadas
  console.log('4. Creando historial de alertas enviadas...');
  const alertHistoryRef = deviceRef.collection('alertHistory');
  for (const alert of SENT_ALERTS) {
    await alertHistoryRef.add({
      type: alert.type,
      timestamp: admin.firestore.Timestamp.fromDate(alert.timestamp),
      location: new admin.firestore.GeoPoint(LOCATION.lat, LOCATION.lng),
      resolved: alert.resolved,
      resolvedAt: alert.resolved ? admin.firestore.FieldValue.serverTimestamp() : null,
      notifiedContacts: EMERGENCY_CONTACTS.map(c => c.uid)
    });
    console.log(`   ✓ ${alert.type} (${alert.timestamp.toLocaleDateString()})`);
  }
  console.log('');
  
  // 5. Crear historial de alertas recibidas
  console.log('5. Creando historial de alertas recibidas...');
  const receivedRef = userRef.collection('receivedAlerts');
  for (const alert of RECEIVED_ALERTS) {
    await receivedRef.add({
      fromUserName: alert.fromName,
      fromDeviceId: 'EXTERNAL_DEVICE',
      type: alert.type,
      timestamp: admin.firestore.Timestamp.fromDate(alert.timestamp),
      location: new admin.firestore.GeoPoint(LOCATION.lat + 0.01, LOCATION.lng + 0.01),
      acknowledged: alert.acknowledged,
      acknowledgedAt: alert.acknowledged ? admin.firestore.FieldValue.serverTimestamp() : null
    });
    console.log(`   ✓ De ${alert.fromName}: ${alert.type}`);
  }
  console.log('');
  
  console.log('═══════════════════════════════════════════');
  console.log('✅ Usuario de prueba configurado exitosamente');
  console.log('═══════════════════════════════════════════');
  console.log(`   Email: ${TEST_USER.email}`);
  console.log(`   Device: ${TEST_DEVICE.id}`);
  console.log(`   Contactos: ${EMERGENCY_CONTACTS.length}`);
  console.log(`   Alertas enviadas: ${SENT_ALERTS.length}`);
  console.log(`   Alertas recibidas: ${RECEIVED_ALERTS.length}`);
  console.log('═══════════════════════════════════════════\n');
  
  process.exit(0);
}

setupTestUser().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
