const admin = require('firebase-admin');
const serviceAccount = require('../wilobu-d21b2-firebase-adminsdk-fbsvc-52fafed2bc.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function createDeviceOwnerIndex() {
  try {
    console.log('🔧 Creando índice de dispositivos con ownerUid\n');

    const usersSnapshot = await db.collection('users').get();
    let updated = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const devicesSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('devices')
        .get();

      for (const deviceDoc of devicesSnapshot.docs) {
        const deviceData = deviceDoc.data();
        
        // Solo actualizar si ownerUid no existe o es diferente
        if (deviceData.ownerUid !== userId) {
          await deviceDoc.ref.update({
            ownerUid: userId
          });
          
          console.log(`✅ Dispositivo ${deviceDoc.id} -> owner: ${userId}`);
          updated++;
        }
      }
    }

    console.log(`\n✅ Índice creado. ${updated} dispositivos actualizados.`);
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

createDeviceOwnerIndex();
