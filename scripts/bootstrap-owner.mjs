// tracktor-railway owner bootstrap.
//
// Creates the deployer's account through Tracktor's own registration endpoint, on loopback, before
// the public listener opens. Without this, the first stranger to find a fresh instance can claim it.
//
// Idempotent: an existing username is reported and left alone. Values are never printed; only
// names, lengths and outcomes.

const base = process.env.TRACKTOR_INTERNAL_URL;
const username = process.env.TRACKTOR_OWNER_USERNAME ?? '';
const password = process.env.TRACKTOR_OWNER_PASSWORD ?? '';

const log = (msg) => console.error(`[tracktor-railway] ${msg}`);
const fail = (msg) => {
  log(`FATAL: ${msg}`);
  process.exit(1);
};

if (!base) fail('TRACKTOR_INTERNAL_URL is not set');
if (username.length < 3) fail('TRACKTOR_OWNER_USERNAME must be at least 3 characters');
// Tracktor's own minimum is 6; 12 is the wrapper's, because this account is reachable from the
// internet the moment the service starts.
if (password.length < 12) fail('TRACKTOR_OWNER_PASSWORD must be at least 12 characters');

const res = await fetch(`${base.replace(/\/$/, '')}/api/auth/register`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username, password })
}).catch((err) => fail(`could not reach Tracktor on loopback: ${err.message}`));

let body = {};
try {
  body = await res.json();
} catch {
  /* a non-JSON body is reported through the status below */
}

if (res.status === 201) {
  log(`owner bootstrap complete: created "${username}" (password length ${password.length})`);
  process.exit(0);
}

const message = String(body?.message ?? body?.error ?? '').toLowerCase();
if (res.status === 400 && message.includes('already exists')) {
  log('owner bootstrap skipped: that account already exists; TRACKTOR_OWNER_PASSWORD is now stale and is ignored');
  process.exit(0);
}

fail(`registration failed with HTTP ${res.status}${message ? `: ${message}` : ''}`);
