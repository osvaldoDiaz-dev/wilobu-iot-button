// Función para migrar dispositivos existentes y agregar campos faltantes
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

exports.migrateDevicesFields = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  const db = admin.firestore();
  let count = 0;

  try {
    const usersSnapshot = await db.collection('users').get();

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();

      const devicesSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('devices')
        .get();

      const batch = db.batch();

      for (const deviceDoc of devicesSnapshot.docs) {
        const deviceData = deviceDoc.data();

        const ownerUid = deviceData.ownerUid || userId;
        const ownerName = deviceData.ownerName || userData.displayName || userData.name || 'Usuario';

        const existingViewers = Array.isArray(deviceData.viewerUids) ? deviceData.viewerUids : [];
        const emergencyContacts = Array.isArray(deviceData.emergencyContacts) ? deviceData.emergencyContacts : [];
        const emergencyUids = emergencyContacts
          .map((c) => (c && typeof c === 'object' ? c.uid : null))
          .filter((v) => typeof v === 'string');

        const merged = Array.from(new Set([...existingViewers, ...emergencyUids]));

        const needsOwner = deviceData.ownerUid !== ownerUid || deviceData.ownerName !== ownerName;
        const needsViewers = merged.length !== existingViewers.length;

        if (needsOwner || needsViewers) {
          batch.update(deviceDoc.ref, {
            ownerUid,
            ownerName,
            viewerUids: merged,
          });
          count++;
        }
      }

      if (!batch._ops || batch._ops.length === 0) continue;
      await batch.commit();
    }

    return {
      success: true,
      migratedCount: count,
      message: `Migrated ${count} devices`
    };
  } catch (error) {
    console.error('Migration error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});
