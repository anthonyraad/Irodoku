// Firebase Auth custom token (RS256 JWT signed by the service account).
// https://firebase.google.com/docs/auth/admin/create-custom-tokens#create_custom_tokens_using_a_third-party_jwt_library
import { parseServiceAccount } from '../../worker/src/firebase.js';

const AUD = 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit';

const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64urlStr = (s) => b64url(new TextEncoder().encode(s));

function pemToDer(pem) {
  const b = atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, ''));
  const out = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) out[i] = b.charCodeAt(i);
  return out.buffer;
}

let keyCache = null; // { pem, key }

export async function mintCustomToken(rawServiceAccount, uid, claims = {}, nowSec = Math.floor(Date.now() / 1000)) {
  const sa = parseServiceAccount(rawServiceAccount);
  if (!sa) throw new Error('FIREBASE_SERVICE_ACCOUNT not set');
  if (!keyCache || keyCache.pem !== sa.private_key) {
    const key = await crypto.subtle.importKey('pkcs8', pemToDer(sa.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
    keyCache = { pem: sa.private_key, key };
  }
  const header = b64urlStr(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const body = b64urlStr(JSON.stringify({
    iss: sa.client_email, sub: sa.client_email, aud: AUD,
    iat: nowSec, exp: nowSec + 3600, uid, claims,
  }));
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', keyCache.key,
    new TextEncoder().encode(`${header}.${body}`));
  return `${header}.${body}.${b64url(sig)}`;
}
