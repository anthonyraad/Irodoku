// firebase-admin RTDB access. Credentials come ONLY from env:
//   FIREBASE_SERVICE_ACCOUNT  (JSON string, or base64 of the JSON)
//   FIREBASE_DATABASE_URL     (e.g. https://<project>-default-rtdb.firebaseio.com)
import admin from 'firebase-admin';

let db = null;
export function getDb() {
  if (db) return db;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  const url = process.env.FIREBASE_DATABASE_URL;
  if (!raw || !url) return null;
  const json = raw.trim().startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(json)), databaseURL: url });
  db = admin.database();
  return db;
}

export async function topPocket(day, n = 10) {
  const d = getDb();
  if (!d) return [];
  const snap = await d.ref(`irodoku_daily/${day}/pocket`).orderByChild('ms').limitToFirst(n).get();
  const rows = [];
  snap.forEach((c) => { const v = c.val(); if (v && typeof v.ms === 'number') rows.push({ name: v.name, ms: v.ms }); });
  return rows.sort((a, b) => a.ms - b.ms);
}

// Same PST (fixed UTC-8) day key as lib/models/daily_irodoku.dart.
export function pstDayKey(date = new Date()) {
  return new Date(date.getTime() - 8 * 3600e3).toISOString().slice(0, 10);
}
