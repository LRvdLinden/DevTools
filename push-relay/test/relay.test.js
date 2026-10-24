import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { message, isNoise, secretFor } from '../src/index.js';

const env = { HOOK_SECRET: 'unit-test-secret', ONESIGNAL_APP_ID: 'app', ONESIGNAL_REST_KEY: 'rest' };
const key = '0f6a3c9e-1b2d-4e5f-8a7b-9c0d1e2f3a4b';

async function sign(secret, body) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const s = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(body));
  return [...new Uint8Array(s)].map(b => b.toString(16).padStart(2, '0')).join('');
}

test('messages', () => {
  const live = message({ data: { type: 'appStoreVersionAppVersionStateUpdated', attributes: { newValue: 'READY_FOR_SALE' } } }, 'Trailhead', 'nl');
  assert.equal(live.body, 'Trailhead staat live in de App Store 🎉');
  assert.equal(message({ data: { type: 'webhookPingCreated' } }, '', 'en').body, 'Test message received. Push notifications work!');
  assert.equal(message({ data: { type: 'buildUploadStateUpdated', attributes: { newState: 'COMPLETE' } } }, 'X', 'de').body, 'Build verarbeitet und bereit für TestFlight');
  assert.ok(isNoise({ data: { type: 'buildUploadStateUpdated', attributes: { newState: 'PROCESSING' } } }));
});

test('register validates input and returns webhook + secret', async () => {
  globalThis.fetch = async () => new Response('{}', { status: 200 });
  const res = await worker.fetch(new Request('https://relay.test/register', { method: 'POST', body: JSON.stringify({ key, token: 'ab'.repeat(32), sandbox: true }) }), env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.webhookURL, `https://relay.test/hook/${key}`);
  assert.equal(body.secret, await secretFor(env, key));
  const bad = await worker.fetch(new Request('https://relay.test/register', { method: 'POST', body: JSON.stringify({ key: 'x', token: 'y' }) }), env);
  assert.equal(bad.status, 400);
  let called = false;
  globalThis.fetch = async () => { called = true; return new Response('{}', { status: 200 }); };
  const sdk = await worker.fetch(new Request('https://relay.test/register', { method: 'POST', body: JSON.stringify({ key }) }), env);
  assert.equal(sdk.status, 200);
  assert.equal(called, false);
});

test('hook checks signature and sends push', async () => {
  let sent;
  globalThis.fetch = async (url, init) => { sent = { url, body: JSON.parse(init.body) }; return new Response('{}', { status: 200 }); };
  const payload = JSON.stringify({ data: { type: 'appStoreVersionAppVersionStateUpdated', id: '1', attributes: { oldValue: 'IN_REVIEW', newValue: 'PENDING_DEVELOPER_RELEASE' } } });
  const secret = await secretFor(env, key);
  const good = await worker.fetch(new Request(`https://relay.test/hook/${key}?app=Trailhead&lang=en`, {
    method: 'POST', body: payload, headers: { 'X-Apple-SIGNATURE': `hmacsha256=${await sign(secret, payload)}` },
  }), env);
  assert.equal(good.status, 200);
  assert.equal(sent.url, 'https://api.onesignal.com/notifications');
  assert.deepEqual(sent.body.include_aliases, { external_id: [key] });
  assert.equal(sent.body.contents.en, 'Trailhead was approved and is ready for release');
  const forged = await worker.fetch(new Request(`https://relay.test/hook/${key}`, {
    method: 'POST', body: payload, headers: { 'X-Apple-SIGNATURE': 'hmacsha256=deadbeef' },
  }), env);
  assert.equal(forged.status, 401);
});
