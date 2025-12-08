// Actualiza la ubicación de todas las alertas recibidas de un usuario
// Ejecutar: node scripts/fix_alert_locations.js
// Requiere credenciales de Firebase Admin (GOOGLE_APPLICATION_CREDENTIALS) o entorno con permisos

const admin = require('firebase-admin');

const TARGET_UID = '7TUEUXvKYiXMPbsanVzN5iaorGI2'; // wilobu.test
const LAT = -23.586574138778996;
const LNG = -70.37831984599329;

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: 'wilobu-d21b2' });
  }
  const db = admin.firestore();
  const gp = new admin.firestore.GeoPoint(LAT, LNG);

  // Actualizar colección receivedAlerts del usuario
  const receivedRef = db.collection('users').doc(TARGET_UID).collection('receivedAlerts');
  const snap = await receivedRef.get();
  console.log(`Encontradas ${snap.size} alertas en receivedAlerts para ${TARGET_UID}`);

  for (const doc of snap.docs) {
    await doc.ref.set({
      location: gp,
      lat: LAT,
      lng: LNG,
      locationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    console.log(`✓ Actualizado receivedAlerts/${doc.id}`);
  }

  // Opcional: alertHistory bajo cada dispositivo del usuario (propio)
  const devicesSnap = await db.collection('users').doc(TARGET_UID).collection('devices').get();
  for (const dev of devicesSnap.docs) {
    const ahRef = dev.ref.collection('alertHistory');
    const ahSnap = await ahRef.get();
    if (ahSnap.empty) continue;
    console.log(`Dispositivo ${dev.id}: ${ahSnap.size} registros en alertHistory`);
    for (const doc of ahSnap.docs) {
      await doc.ref.set({
        location: { geopoint: gp },
        lat: LAT,
        lng: LNG,
        locationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      console.log(`✓ Actualizado alertHistory/${dev.id}/${doc.id}`);
    }
  }

  console.log('Terminado.');
  process.exit(0);
}

main().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
