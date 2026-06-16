
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    // Add your Firebase Storage bucket to .env: STORAGE_BUCKET=<project-id>.appspot.com
    storageBucket: process.env.STORAGE_BUCKET,
});

const db = admin.firestore();
const storage = admin.storage();
module.exports = { db, admin, storage };
