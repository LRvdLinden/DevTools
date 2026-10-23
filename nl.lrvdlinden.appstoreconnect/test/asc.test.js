'use strict';
/* Offline tests: JWT, sales parsing/aggregation and a full app refresh with a mocked Homey + API. */
const assert = require('assert');
const crypto = require('crypto');
const Module = require('module');
const path = require('path');
const fs = require('fs');
const os = require('os');

// ---- 1. JWT ----
const { makeToken, parseSales, AscClient } = require('../lib/asc');
const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
const token = makeToken({ issuerId: 'iss', keyId: 'KEY123', privateKey: pem });
const [h, p, s] = token.split('.');
const ok = crypto.verify('sha256', Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url'));
assert(ok, 'JWT signature must verify');
const payload = JSON.parse(Buffer.from(p, 'base64url'));
assert.strictEqual(payload.aud, 'appstoreconnect-v1');
assert(payload.exp - payload.iat <= 1200, 'token lifetime <= 20 min');
console.log('✓ JWT ES256');

// ---- 2. Sales parsing ----
const header = 'Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tBegin Date\tEnd Date\tCustomer Currency\tCountry Code\tCurrency of Proceeds\tApple Identifier\tCustomer Price\tPromo Code\tParent Identifier\tSubscription\tPeriod\tCategory\tCMB\tDevice';
const row = (sku, type, units, proceeds, apple, parent = '') => `APPLE\tUS\t${sku}\tDev\tTitle\t1.0\t${type}\t${units}\t${proceeds}\t10/20/2026\t10/20/2026\tEUR\tNL\tEUR\t${apple}\t0\t\t${parent}\t\t\tUtilities\t\tiPhone`;
const tsv = [header, row('TRAIL', '1F', 10, 0, '111'), row('TRAIL', '3F', 2, 0, '111'), row('TRAIL', '7F', 50, 0, '111'),
  row('TRAIL.PRO', 'IA1', 3, 2.1, '999', 'TRAIL'), row('LUMEN', '1', 5, 0, '222')].join('\n');
const rows = parseSales(tsv);
assert.strictEqual(rows.length, 5);
assert.strictEqual(rows.find(r => r.kind === 'iap').parentId, 'TRAIL');
console.log('✓ sales TSV parsing');

// ---- 3. Aggregation ----
const { aggregate } = require('../lib/sales');
const apps = [{ id: '111', sku: 'TRAIL' }, { id: '222', sku: 'LUMEN' }];
const days = [];
for (let i = 0; i < 20; i++) days.push({ date: `2026-10-${String(i + 1).padStart(2, '0')}`, rows });
const agg = aggregate(apps, days, rows.concat(rows));
assert.strictEqual(agg.perApp['111'].yesterday, 12);
assert.strictEqual(agg.perApp['111'].last7, 84);
assert.strictEqual(agg.perApp['222'].last30, 100);
assert.strictEqual(agg.perApp['111'].total, 24);
assert.strictEqual(agg.portfolio.yesterday, 17);
assert(Math.abs(agg.perApp['111'].proceeds30 - 2.1 * 3 * 20) < 1e-6, 'IAP proceeds attributed to parent app');
assert.strictEqual(agg.currency, 'EUR');
console.log('✓ aggregation (per app, portfolio, IAP → parent)');

// ---- 4. Full app run with mocked Homey ----
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'asc-'));
const triggered = [];
const settingsStore = { accounts: [{ id: 'a1', name: 'PixelForges', issuerId: 'iss', keyId: 'KEY123', privateKey: pem, vendorNumber: '85734756' }] };
const card = id => ({ trigger: async (...args) => { triggered.push(id); }, registerRunListener: fn => { cards[id] = fn; } });
const cards = {};
const devices = { asc_app: [], asc_portfolio: [] };
class Base { constructor() { } log() {} error(...a) { console.error('APP ERROR', ...a); } }
const homeyMock = {
  App: Base, Driver: Base,
  Device: class extends Base {
    constructor(data) { super(); this._data = data; this.caps = {}; }
    getData() { return this._data; } hasCapability() { return true; } getCapabilityValue(c) { return this.caps[c]; }
    async setCapabilityValue(c, v) { this.caps[c] = v; } getAvailable() { return true; } async setSettings() {}
  },
};
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (req, ...rest) { if (req === 'homey') return 'homey'; return origResolve.call(this, req, ...rest); };
require.cache.homey = { id: 'homey', filename: 'homey', loaded: true, exports: homeyMock };

// Mock API
const sales = require('../lib/sales');
sales.SalesStore.prototype.daily = async () => days;
sales.SalesStore.prototype.lifetime = async () => rows;
let reviewSet = [{ id: 'r1', rating: 5, title: 'Great', body: 'Love it', author: 'anna', territory: 'NLD', created: '2026-10-20' }];
let state2 = 'PREPARE_FOR_SUBMISSION';
AscClient.prototype.apps = async () => [{ id: '111', name: 'Trailhead', bundleId: 'com.x.trail', sku: 'TRAIL' }, { id: '222', name: 'Lumen', bundleId: 'com.x.lumen', sku: 'LUMEN' }];
AscClient.prototype.versions = async id => (id === '111'
  ? [{ id: 'v2', version: '2.5.0', state: state2, created: '2026-10-22' }, { id: 'v1', version: '2.4.1', state: 'READY_FOR_SALE', created: '2026-09-01' }]
  : [{ id: 'v3', version: '1.0', state: 'READY_FOR_DISTRIBUTION', created: '2026-10-01' }]);
AscClient.prototype.builds = async () => [{ id: 'b1', number: '318', version: '2.5.0', processingState: 'VALID', internalState: 'IN_BETA_TESTING', externalState: '', expired: false }];
AscClient.prototype.reviews = async () => reviewSet;
AscClient.prototype.releaseVersion = async () => ({});
require('../lib/asc').storeLookup = async () => ({});

const App = require('../app.js');
const app = new App();
app.homey = {
  i18n: { getLanguage: () => 'nl' },
  __: k => k,
  settings: { get: k => settingsStore[k], set: (k, v) => { settingsStore[k] = v; }, on: () => {} },
  setTimeout: () => {}, setInterval: () => 1, clearInterval: () => {},
  api: { realtime: () => {} },
  flow: { getDeviceTriggerCard: card, getTriggerCard: card, getConditionCard: card, getActionCard: card },
  dashboards: { getWidget: () => ({ registerSettingAutocompleteListener: () => {} }) },
  drivers: { getDriver: id => ({ getDevices: () => devices[id] }) },
};
app.sales = null;

(async () => {
  await app.onInit();
  app.sales = new sales.SalesStore({ dir: tmp });
  const AppDevice = require('../drivers/asc_app/device.js');
  const PortDevice = require('../drivers/asc_portfolio/device.js');
  const dev = new AppDevice({ id: '111' }); dev.homey = app.homey; dev.homey.app = app;
  const port = new PortDevice({ id: 'portfolio' }); port.homey = app.homey;
  devices.asc_app.push(dev); devices.asc_portfolio.push(port);

  await app.refreshAll({ sales: true });
  assert.strictEqual(dev.caps.asc_status, 'Voorbereiden');
  assert.strictEqual(dev.caps.asc_version_live, '2.4.1');
  assert.strictEqual(dev.caps.asc_downloads_yesterday, 12);
  assert.strictEqual(dev.caps.asc_downloads_total, 12);
  assert.strictEqual(port.caps.asc_apps_live, 1, 'only Ready for Sale counts as live');
  assert.strictEqual(port.caps.asc_apps_attention, 1, 'Ready for Distribution needs attention');
  assert.strictEqual(triggered.length, 0, 'no triggers on first run');
  console.log('✓ first refresh fills devices (status NL, live only Ready for Sale)');

  state2 = 'WAITING_FOR_REVIEW';
  reviewSet = [{ id: 'r2', rating: 3, title: 'Ok', body: 'meh', author: 'bob', territory: 'USA' }, ...reviewSet];
  await app.refreshAll({ sales: false });
  for (const id of ['status_changed', 'entered_review', 'any_status_changed', 'any_entered_review', 'new_customer_review', 'any_new_customer_review']) {
    assert(triggered.includes(id), `trigger ${id} fired`);
  }
  assert.strictEqual(dev.caps.asc_in_review, true);
  console.log('✓ triggers: status changed, entered review, new review');

  assert.strictEqual(await cards.is_in_review({ device: dev }), true);
  assert.strictEqual(await cards.downloads_yesterday_above({ device: dev, number: 10 }), true);
  assert.strictEqual(await cards.is_live({ device: dev }), true);
  console.log('✓ conditions');

  const w = app.widgetData();
  assert.strictEqual(w.apps.length, 2);
  assert(w.portfolio.history.length === 20 && w.hasSales);
  console.log('✓ widget data');
  console.log('\nAll tests passed');
})().catch(err => { console.error(err); process.exit(1); });
