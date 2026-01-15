const admin = require("firebase-admin");

// サービスアカウントキー
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
});

const uid = "gZcntXE7W5RmoYluLRO1UF7nNjb2";

(async () => {
    await admin.auth().setCustomUserClaims(uid, { role: "admin" });
    console.log("✅ admin role claim set for:", uid);
    process.exit(0);
})();
