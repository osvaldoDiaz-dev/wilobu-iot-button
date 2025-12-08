const admin = require('firebase-admin');
const serviceAccount = require('../wilobu-d21b2-firebase-adminsdk-fbsvc-52fafed2bc.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function fixMonitoredDevices() {
  try {
    console.log('🔧 CORRIGIENDO monitored_devices\n');

    const usersSnapshot = await db.collection('users').get();
    let fixed = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      
      // Buscar todos los dispositivos donde este usuario es viewer
      const devicesSnapshot = await db.collectionGroup('devices').get();
      
      const devicesToMonitor = [];
      
      for (const deviceDoc of devicesSnapshot.docs) {
        const deviceData = deviceDoc.data();
        const viewerUids = deviceData.viewerUids || [];
        
        if (viewerUids.includes(userId)) {
          devicesToMonitor.push(deviceDoc.id);
        }
      }
      
      if (devicesToMonitor.length > 0) {
        await db.collection('users').doc(userId).set({
          monitored_devices: devicesToMonitor
        }, { merge: true });
        
        const userData = userDoc.data();
        console.log(`✅ Usuario ${userData.email || userId}:`);
        console.log(`   Añadidos ${devicesToMonitor.length} dispositivos:`, devicesToMonitor);
        fixed++;
      }
    }

    console.log(`\n✅ Corrección completada. ${fixed} usuarios actualizados.`);
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

fixMonitoredDevices();
