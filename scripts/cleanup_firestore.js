/**
 * Script para limpiar datos de prueba en Firestore
 * Mantiene: osvaldo, daniela, elbarsimson, axel, usuario de prueba
 * Elimina: dispositivos ficticios, datos de prueba
 * 
 * Ejecutar: node scripts/cleanup_firestore.js
 * Requiere: firebase-admin configurado
 */

const admin = require('firebase-admin');

// UIDs de usuarios a MANTENER (no borrar sus datos)
const PROTECTED_USERS = {
  'rEIrSQPTHIel9ySQWX2cWlL6HGX2': 'elbarsimson',
  '7TUEUXvKYiXMPbsanVzN5iaorGI2': 'wilobu.test',
  // Añadir UIDs de osvaldo, daniela, axel cuando se conozcan
};

// Emails protegidos
const PROTECTED_EMAILS = [
  'elbarsimson9593@gmail.com',
  'wilobu.test@gmail.com',
  'osvaldo',  // Añadir email completo
  'daniela',  // Añadir email completo
  'axel',     // Añadir email completo
];

// Device IDs reales (del firmware)
const REAL_DEVICES = [
  '781C3CB994FC',  // Dispositivo de firmware real
];

async function cleanupFirestore() {
  console.log('🧹 Iniciando limpieza de Firestore...\n');
  
  // Inicializar Firebase Admin (requiere credenciales)
  if (!admin.apps.length) {
    // Usar credenciales de entorno o archivo
    admin.initializeApp({
      projectId: 'wilobu-d21b2',
    });
  }
  
  const db = admin.firestore();
  
  // === 1. LISTAR TODOS LOS USUARIOS ===
  console.log('📋 Listando usuarios...');
  const usersSnapshot = await db.collection('users').get();
  
  const usersToKeep = [];
  const usersToReview = [];
  
  usersSnapshot.forEach(doc => {
    const data = doc.data();
    const uid = doc.id;
    const email = data.email || 'Sin email';
    
    if (PROTECTED_USERS[uid] || PROTECTED_EMAILS.some(e => email.includes(e))) {
      usersToKeep.push({ uid, email, name: data.name || 'Sin nombre' });
    } else {
      usersToReview.push({ uid, email, name: data.name || 'Sin nombre' });
    }
  });
  
  console.log('\n✅ Usuarios a MANTENER:');
  usersToKeep.forEach(u => console.log(`   - ${u.email} (${u.name})`));
  
  console.log('\n⚠️ Usuarios a REVISAR (posible eliminación):');
  usersToReview.forEach(u => console.log(`   - ${u.email} (${u.name}) [${u.uid}]`));
  
  // === 2. LISTAR DISPOSITIVOS POR USUARIO ===
  console.log('\n📱 Dispositivos por usuario:');
  
  for (const user of usersToKeep) {
    const devicesSnapshot = await db
      .collection('users')
      .doc(user.uid)
      .collection('devices')
      .get();
    
    console.log(`\n   ${user.email}:`);
    
    const devicesToKeep = [];
    const devicesToDelete = [];
    
    devicesSnapshot.forEach(doc => {
      const deviceId = doc.id;
      const data = doc.data();
      
      if (REAL_DEVICES.includes(deviceId)) {
        devicesToKeep.push({ id: deviceId, status: data.status });
      } else {
        devicesToDelete.push({ id: deviceId, status: data.status });
      }
    });
    
    devicesToKeep.forEach(d => console.log(`      ✅ ${d.id} (${d.status}) - REAL`));
    devicesToDelete.forEach(d => console.log(`      ❌ ${d.id} (${d.status}) - FICTICIO`));
  }
  
  // === 3. RESUMEN DE ACCIONES ===
  console.log('\n' + '='.repeat(50));
  console.log('📊 RESUMEN DE LIMPIEZA PROPUESTA:');
  console.log('='.repeat(50));
  console.log(`   Usuarios a mantener: ${usersToKeep.length}`);
  console.log(`   Usuarios a revisar: ${usersToReview.length}`);
  console.log(`   Dispositivos reales: ${REAL_DEVICES.length}`);
  console.log('\n⚠️ Este script solo lista. Para eliminar, descomentar el código de eliminación.');
  
  /*
  // === CÓDIGO DE ELIMINACIÓN (DESCOMENTAR CON CUIDADO) ===
  
  // Eliminar dispositivos ficticios
  for (const user of usersToKeep) {
    const devicesSnapshot = await db
      .collection('users')
      .doc(user.uid)
      .collection('devices')
      .get();
    
    for (const doc of devicesSnapshot.docs) {
      if (!REAL_DEVICES.includes(doc.id)) {
        console.log(`   Eliminando dispositivo ficticio: ${doc.id}`);
        await doc.ref.delete();
      }
    }
  }
  
  // Limpiar alertas de prueba viejas (más de 7 días)
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - 7);
  
  for (const user of usersToKeep) {
    const alertsSnapshot = await db
      .collection('users')
      .doc(user.uid)
      .collection('receivedAlerts')
      .where('timestamp', '<', cutoffDate)
      .get();
    
    for (const doc of alertsSnapshot.docs) {
      console.log(`   Eliminando alerta vieja: ${doc.id}`);
      await doc.ref.delete();
    }
  }
  */
  
  console.log('\n✅ Análisis completado');
}

// Ejecutar
cleanupFirestore()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
