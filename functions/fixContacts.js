const functions = require('firebase-functions');
const admin = require('firebase-admin');

exports.fixBidirectionalContacts = functions.https.onRequest(async (req, res) => {
  try {
    const db = admin.firestore();
    let fixed = 0;

    const usersSnapshot = await db.collection('users').get();

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const monitoredDevices = userData.monitored_devices || [];

      if (monitoredDevices.length === 0) continue;

      for (const deviceId of monitoredDevices) {
        const deviceQuery = await db.collectionGroup('devices')
          .where(admin.firestore.FieldPath.documentId(), '==', deviceId)
          .get();

        if (deviceQuery.empty) continue;

        const deviceDoc = deviceQuery.docs[0];
        const deviceData = deviceDoc.data();
        const ownerId = deviceData.ownerUid;

        if (!ownerId || ownerId === userId) continue;

        const viewerDevicesSnapshot = await db
          .collection('users')
          .doc(userId)
          .collection('devices')
          .get();

        if (viewerDevicesSnapshot.empty) continue;

        const viewerDeviceIds = viewerDevicesSnapshot.docs.map(d => d.id);

        await db.collection('users').doc(ownerId).update({
          monitored_devices: admin.firestore.FieldValue.arrayUnion(...viewerDeviceIds)
        });

        fixed++;
      }
    }

    res.json({ success: true, fixed });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: error.message });
  }
});
