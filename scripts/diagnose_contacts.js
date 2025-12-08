const admin = require('firebase-admin');
const serviceAccount = require('../wilobu-d21b2-firebase-adminsdk-fbsvc-52fafed2bc.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function diagnoseContacts() {
  try {
    console.log('📊 DIAGNÓSTICO DE CONTACTOS\n');

    const usersSnapshot = await db.collection('users').get();
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      
      console.log(`\n👤 Usuario: ${userId}`);
      console.log(`   Email: ${userData.email || 'N/A'}`);
      console.log(`   Nombre: ${userData.displayName || 'N/A'}`);
      
      // Monitored devices
      const monitoredDevices = userData.monitored_devices || [];
      console.log(`   📱 Monitored Devices (${monitoredDevices.length}):`, monitoredDevices);
      
      // Dispositivos propios
      const devicesSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('devices')
        .get();
      
      console.log(`   🔧 Dispositivos Propios (${devicesSnapshot.size}):`);
      
      for (const deviceDoc of devicesSnapshot.docs) {
        const deviceData = deviceDoc.data();
        console.log(`      - ${deviceDoc.id}`);
        console.log(`        Nickname: ${deviceData.nickname || 'N/A'}`);
        console.log(`        Owner: ${deviceData.ownerUid || 'N/A'}`);
        console.log(`        Emergency Contacts:`, deviceData.emergencyContacts || []);
        console.log(`        Viewer UIDs:`, deviceData.viewerUids || []);
      }
    }
    
    console.log('\n✅ Diagnóstico completado');
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

diagnoseContacts();
