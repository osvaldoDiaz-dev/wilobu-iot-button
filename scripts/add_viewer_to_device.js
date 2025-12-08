const admin = require('firebase-admin');
const serviceAccount = require('../firebaseServiceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function addViewerToDevice() {
  try {
    // Get test users
    const users = await db.collection('users').limit(2).get();
    if (users.size < 2) {
      console.error('Need at least 2 test users');
      return;
    }

    const userIds = users.docs.map(doc => doc.id);
    const owner = userIds[0];
    const viewer = userIds[1];

    console.log(`Owner: ${owner}`);
    console.log(`Viewer: ${viewer}`);

    // Find a device owned by the first user
    const devices = await db.collection(`users/${owner}/devices`).limit(1).get();
    if (devices.size === 0) {
      console.error('No devices found for owner');
      return;
    }

    const deviceId = devices.docs[0].id;
    console.log(`Device: ${deviceId}`);

    // Add viewer UID to viewerUids array
    await db.collection(`users/${owner}/devices`).doc(deviceId).update({
      viewerUids: admin.firestore.FieldValue.arrayUnion([viewer]),
    });

    console.log(`Successfully added ${viewer} as viewer to device ${deviceId}`);
  } catch (error) {
    console.error('Error:', error);
  } finally {
    process.exit(0);
  }
}

addViewerToDevice();
