const admin = require('firebase-admin');
const serviceAccount = require('../wilobu-d21b2-firebase-adminsdk-fbsvc-52fafed2bc.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function createDeviceMap() {
  try {
    console.log('🗺️  Creando mapa de dispositivos\n');

    const usersSnapshot = await db.collection('users').get();
    const deviceMap = {};

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const devicesSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('devices')
        .get();

      for (const deviceDoc of devicesSnapshot.docs) {
        deviceMap[deviceDoc.id] = userId;
        console.log(`  ${deviceDoc.id} -> ${userId}`);
      }
    }

    // Guardar mapa en Firestore para consulta rápida
    await db.collection('system').doc('deviceOwnerMap').set({
      map: deviceMap,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log(`\n✅ Mapa creado con ${Object.keys(deviceMap).length} dispositivos`);
    console.log(JSON.stringify(deviceMap, null, 2));
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

createDeviceMap();
