const admin = require('firebase-admin');
const serviceAccount = require('../firebaseServiceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function migrateMonitoredDevices() {
  let count = 0;
  let updated = 0;

  try {
    // Recorrer todos los usuarios
    const usersSnapshot = await db.collection('users').get();

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();

      // Recorrer todos los dispositivos de todos los usuarios
      const allUsersDevices = await db.collectionGroup('devices').get();

      const monitoredDevices = new Set();

      // Buscar dispositivos donde este usuario es viewer
      for (const deviceDoc of allUsersDevices.docs) {
        const deviceData = deviceDoc.data();
        const viewerUids = Array.isArray(deviceData.viewerUids) ? deviceData.viewerUids : [];

        if (viewerUids.includes(userId)) {
          monitoredDevices.add(deviceDoc.id);
          count++;
        }
      }

      // Si encontró dispositivos, actualizar usuario
      if (monitoredDevices.size > 0) {
        const existingMonitored = userData.monitored_devices || [];
        const merged = Array.from(new Set([...existingMonitored, ...monitoredDevices]));

        if (merged.length > existingMonitored.length) {
          await db.collection('users').doc(userId).update({
            monitored_devices: merged,
          });
          updated++;
          console.log(`✓ Usuario ${userId}: agregados ${merged.length} dispositivos`);
        }
      }
    }

    console.log(`\n✅ Migración completada: ${updated} usuarios actualizados con ${count} dispositivos totales`);
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

migrateMonitoredDevices();
