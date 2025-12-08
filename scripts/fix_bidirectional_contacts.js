const admin = require('firebase-admin');
const serviceAccount = require('../wilobu-d21b2-firebase-adminsdk-fbsvc-52fafed2bc.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function fixBidirectionalContacts() {
  try {
    console.log('🔍 Buscando relaciones unidireccionales...\n');

    const usersSnapshot = await db.collection('users').get();
    let fixed = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const monitoredDevices = userData.monitored_devices || [];

      if (monitoredDevices.length === 0) continue;

      console.log(`\n👤 Usuario: ${userId} (${userData.email || 'sin email'})`);
      console.log(`   Monitoreando: ${monitoredDevices.length} dispositivos`);

      // Para cada dispositivo que monitorea
      for (const deviceId of monitoredDevices) {
        // Buscar el owner del dispositivo
        const deviceQuery = await db.collectionGroup('devices')
          .where(admin.firestore.FieldPath.documentId(), '==', deviceId)
          .get();

        if (deviceQuery.empty) {
          console.log(`   ⚠️  Dispositivo ${deviceId} no encontrado`);
          continue;
        }

        const deviceDoc = deviceQuery.docs[0];
        const deviceData = deviceDoc.data();
        const ownerId = deviceData.ownerUid;

        if (!ownerId) {
          console.log(`   ⚠️  Dispositivo ${deviceId} sin owner`);
          continue;
        }

        if (ownerId === userId) {
          console.log(`   ℹ️  ${deviceId} es propio, skip`);
          continue;
        }

        console.log(`   📡 Dispositivo ${deviceId} pertenece a: ${ownerId}`);

        // Obtener dispositivos del viewer (usuario actual)
        const viewerDevicesSnapshot = await db
          .collection('users')
          .doc(userId)
          .collection('devices')
          .get();

        if (viewerDevicesSnapshot.empty) {
          console.log(`   ℹ️  Viewer no tiene dispositivos propios`);
          continue;
        }

        const viewerDeviceIds = viewerDevicesSnapshot.docs.map(d => d.id);
        console.log(`   🔧 Viewer tiene ${viewerDeviceIds.length} dispositivos`);

        // Verificar si el owner ya tiene estos dispositivos en monitored_devices
        const ownerDoc = await db.collection('users').doc(ownerId).get();
        const ownerData = ownerDoc.data() || {};
        const ownerMonitored = ownerData.monitored_devices || [];

        const needsUpdate = viewerDeviceIds.some(vd => !ownerMonitored.includes(vd));

        if (needsUpdate) {
          await db.collection('users').doc(ownerId).update({
            monitored_devices: admin.firestore.FieldValue.arrayUnion(...viewerDeviceIds)
          });
          console.log(`   ✅ Añadidos ${viewerDeviceIds.length} dispositivos a monitored_devices del owner`);
          fixed++;
        } else {
          console.log(`   ✓  Owner ya tiene los dispositivos en monitored_devices`);
        }
      }
    }

    console.log(`\n✅ Migración completada. ${fixed} relaciones corregidas.`);
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

fixBidirectionalContacts();
