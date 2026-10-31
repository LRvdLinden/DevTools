'use strict';

/**
 * Minimal App Store Connect API client (https://developer.apple.com/documentation/appstoreconnectapi)
 * with no external dependencies: ES256 JWT, JSON:API requests and gzip Sales Reports.
 */
const crypto = require('crypto');
const https = require('https');
const zlib = require('zlib');

const HOST = 'api.appstoreconnect.apple.com';

class AscError extends Error {
  constructor(message, status = 0) {
    super(message);
    this.status = status;
  }
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function normalizeKey(pem) {
  let key = String(pem || '').trim();
  if (!key.includes('BEGIN')) {
    key = `-----BEGIN PRIVATE KEY-----\n${key.replace(/\s+/g, '').match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----`;
  }
  return key;
}

function makeToken(account) {
  if (!account || !account.issuerId || !account.keyId || !account.privateKey) {
    throw new AscError('Issuer ID, Key ID and private key (.p8) are required');
  }
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'ES256', kid: account.keyId.trim(), typ: 'JWT' };
  const payload = { iss: account.issuerId.trim(), iat: now - 10, exp: now + 1100, aud: 'appstoreconnect-v1' };
  const signing = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  let key;
  try {
    key = crypto.createPrivateKey(normalizeKey(account.privateKey));
  } catch (err) {
    throw new AscError(`Invalid .p8 private key: ${err.message}`);
  }
  const sig = crypto.sign('sha256', Buffer.from(signing), { key, dsaEncoding: 'ieee-p1363' });
  return `${signing}.${b64url(sig)}`;
}

function buildPath(path, query) {
  if (!query || !Object.keys(query).length) return path;
  const q = Object.entries(query)
    .filter(([, v]) => v !== undefined && v !== null)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
  return `${path}${path.includes('?') ? '&' : '?'}${q}`;
}

function rawRequest({ host = HOST, method = 'GET', path, headers = {}, body, timeout = 30000 }) {
  return new Promise((resolve, reject) => {
    const req = https.request({ host, method, path, headers, timeout }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
    });
    req.on('timeout', () => req.destroy(new AscError('Request timed out')));
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

function appleError(buf, status) {
  let detail = '';
  try {
    const parsed = JSON.parse(buf.toString('utf8'));
    detail = (parsed.errors || []).map(e => e.detail || e.title || e.code).join('\n');
  } catch (e) {
    detail = buf.toString('utf8').slice(0, 300);
  }
  const prefix = {
    401: 'Authentication failed (401). Check Issuer ID, Key ID and the .p8 key.',
    403: 'Forbidden (403). The API key role does not allow this.',
    404: 'Not found (404).',
    409: 'Apple refused this change (409).',
    429: 'Too many requests (429).',
  }[status] || `Apple API error ${status}.`;
  return new AscError(detail ? `${prefix} ${detail}` : prefix, status);
}

class AscClient {
  constructor(account, { log = () => {} } = {}) {
    this.account = account;
    this.log = log;
    this._token = null;
    this._tokenExp = 0;
  }

  token() {
    if (!this._token || Date.now() / 1000 > this._tokenExp - 60) {
      this._token = makeToken(this.account);
      this._tokenExp = Math.floor(Date.now() / 1000) + 1100;
    }
    return this._token;
  }

  async request(method, path, { query, body, accept = 'application/json' } = {}) {
    const fullPath = path.startsWith('https://') ? path.replace(`https://${HOST}`, '') : buildPath(path, query);
    const payload = body ? Buffer.from(JSON.stringify(body)) : undefined;
    const headers = { Authorization: `Bearer ${this.token()}`, Accept: accept };
    if (payload) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = payload.length;
    }
    const res = await rawRequest({ method, path: fullPath, headers, body: payload });
    if (res.status < 200 || res.status >= 300) throw appleError(res.body, res.status);
    return res;
  }

  async get(path, query) {
    const res = await this.request('GET', path, { query });
    return JSON.parse(res.body.toString('utf8'));
  }

  async all(path, query, max = 1000) {
    let next = buildPath(path, query);
    const data = [];
    const included = [];
    const seen = new Set();
    while (next && !seen.has(next) && data.length < max) {
      seen.add(next);
      const res = await this.request('GET', next);
      const doc = JSON.parse(res.body.toString('utf8'));
      data.push(...(doc.data || []));
      included.push(...(doc.included || []));
      next = doc.links && doc.links.next ? doc.links.next.replace(`https://${HOST}`, '') : null;
    }
    return { data, included };
  }

  async write(method, path, body) {
    const res = await this.request(method, path, { body });
    const text = res.body.toString('utf8');
    return text ? JSON.parse(text) : null;
  }

  // ---------- Apps ----------

  async apps() {
    const { data } = await this.all('/v1/apps', { limit: 200, 'fields[apps]': 'name,bundleId,sku,primaryLocale' }, 400);
    return data.map(a => ({ id: a.id, name: a.attributes.name, bundleId: a.attributes.bundleId, sku: a.attributes.sku }));
  }

  async versions(appId) {
    const doc = await this.get(`/v1/apps/${appId}/appStoreVersions`, { limit: 12 });
    return (doc.data || []).map(v => ({
      id: v.id,
      version: v.attributes.versionString,
      platform: v.attributes.platform,
      // appStoreState says READY_FOR_SALE only when really live; appVersionState is used as fallback.
      state: v.attributes.appStoreState || v.attributes.appVersionState || '',
      created: v.attributes.createdDate,
      releaseType: v.attributes.releaseType,
    })).sort((a, b) => new Date(b.created || 0) - new Date(a.created || 0));
  }

  async builds(appId, limit = 3) {
    const doc = await this.get('/v1/builds', {
      'filter[app]': appId, sort: '-uploadedDate', limit, include: 'preReleaseVersion,buildBetaDetail',
    });
    const inc = doc.included || [];
    const find = rel => rel && rel.data && inc.find(i => i.type === rel.data.type && i.id === rel.data.id);
    return (doc.data || []).map(b => {
      const pre = find(b.relationships && b.relationships.preReleaseVersion);
      const beta = find(b.relationships && b.relationships.buildBetaDetail);
      const icon = b.attributes.iconAssetToken && b.attributes.iconAssetToken.templateUrl;
      return {
        id: b.id,
        number: b.attributes.version,
        version: pre ? pre.attributes.version : '',
        processingState: b.attributes.processingState,
        expired: !!b.attributes.expired,
        uploaded: b.attributes.uploadedDate,
        internalState: beta ? beta.attributes.internalBuildState : '',
        externalState: beta ? beta.attributes.externalBuildState : '',
        iconUrl: icon ? icon.replace('{w}', '256').replace('{h}', '256').replace('{f}', 'png') : null,
      };
    });
  }

  async reviews(appId, limit = 20) {
    const doc = await this.get(`/v1/apps/${appId}/customerReviews`, { sort: '-createdDate', limit });
    return (doc.data || []).map(r => ({
      id: r.id,
      rating: r.attributes.rating,
      title: r.attributes.title || '',
      body: r.attributes.body || '',
      author: r.attributes.reviewerNickname || '',
      territory: r.attributes.territory || '',
      created: r.attributes.createdDate,
    }));
  }

  async respondToReview(reviewId, text) {
    return this.write('POST', '/v1/customerReviewResponses', {
      data: {
        type: 'customerReviewResponses',
        attributes: { responseBody: text },
        relationships: { review: { data: { type: 'customerReviews', id: reviewId } } },
      },
    });
  }

  async releaseVersion(versionId) {
    return this.write('POST', '/v1/appStoreVersionReleaseRequests', {
      data: {
        type: 'appStoreVersionReleaseRequests',
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: versionId } } },
      },
    });
  }

  // ---------- TestFlight ----------

  /** Installs, sessions, crashes, feedback and invites of one build (no query parameters allowed). */
  async betaUsage(buildId) {
    const res = await this.request('GET', `/v1/builds/${buildId}/metrics/betaBuildUsages`);
    const u = { installs: 0, sessions: 0, crashes: 0, feedback: 0, invites: 0 };
    const walk = node => {
      if (Array.isArray(node)) { node.forEach(walk); return; }
      if (!node || typeof node !== 'object') return;
      if (node.values && typeof node.values === 'object') {
        const v = node.values;
        u.installs += Number(v.installCount) || 0;
        u.sessions += Number(v.sessionCount) || 0;
        u.crashes += Number(v.crashCount) || 0;
        u.feedback += Number(v.feedbackCount) || 0;
        u.invites += Number(v.inviteCount) || 0;
      }
      for (const [k, v] of Object.entries(node)) if (k !== 'values') walk(v);
    };
    try { walk(JSON.parse(res.body.toString('utf8'))); } catch (e) { /* empty metrics */ }
    return u;
  }

  async betaTesterCount(appId) {
    const doc = await this.get('/v1/betaTesters', { 'filter[apps]': appId, limit: 1, 'fields[betaTesters]': 'state' });
    return doc.meta && doc.meta.paging && typeof doc.meta.paging.total === 'number' ? doc.meta.paging.total : (doc.data || []).length;
  }

  /** Latest TestFlight feedback ('screenshot' or 'crash') with its build number. */
  async feedback(appId, kind, limit = 5) {
    const type = kind === 'crash' ? 'betaFeedbackCrashSubmissions' : 'betaFeedbackScreenshotSubmissions';
    const doc = await this.get(`/v1/apps/${appId}/${type}`, { limit, sort: '-createdDate', include: 'build,tester' });
    const inc = doc.included || [];
    const find = rel => rel && rel.data && inc.find(i => i.type === rel.data.type && i.id === rel.data.id);
    return (doc.data || []).map(f => {
      const a = f.attributes || {};
      const build = find(f.relationships && f.relationships.build);
      const tester = find(f.relationships && f.relationships.tester);
      const testerName = tester ? [tester.attributes.firstName, tester.attributes.lastName].filter(Boolean).join(' ') : '';
      return {
        id: f.id,
        created: a.createdDate,
        comment: a.comment || '',
        tester: testerName || a.email || '',
        device: a.deviceModel || '',
        osVersion: a.osVersion || '',
        build: build ? build.attributes.version || '' : '',
      };
    });
  }

  // ---------- Phased release ----------

  async phasedRelease(versionId) {
    try {
      const doc = await this.get(`/v1/appStoreVersions/${versionId}/appStoreVersionPhasedRelease`);
      if (!doc.data) return null;
      const a = doc.data.attributes || {};
      return { id: doc.data.id, state: a.phasedReleaseState || '', day: a.currentDayNumber || 0, start: a.startDate || null };
    } catch (err) {
      if (err.status === 404) return null;
      throw err;
    }
  }

  async setPhasedRelease(id, state) {
    return this.write('PATCH', `/v1/appStoreVersionPhasedReleases/${id}`, {
      data: { type: 'appStoreVersionPhasedReleases', id, attributes: { phasedReleaseState: state } },
    });
  }

  // ---------- Xcode Cloud ----------

  /** Workflows of the app's Xcode Cloud product ([] when Xcode Cloud isn't set up). */
  async ciWorkflows(appId) {
    let product;
    try { product = await this.get(`/v1/apps/${appId}/ciProduct`); } catch (err) { if (err.status === 404) return []; throw err; }
    if (!product.data) return [];
    const doc = await this.get(`/v1/ciProducts/${product.data.id}/workflows`, { limit: 50 });
    return (doc.data || []).map(w => ({ id: w.id, name: w.attributes.name, enabled: w.attributes.isEnabled !== false }));
  }

  async latestBuildRun(workflowId) {
    const doc = await this.get(`/v1/ciWorkflows/${workflowId}/buildRuns`, { limit: 1, sort: '-number' });
    const r = (doc.data || [])[0];
    if (!r) return null;
    const a = r.attributes || {};
    return { id: r.id, number: a.number, progress: a.executionProgress, result: a.completionStatus || '', finished: a.finishedDate || null };
  }

  async startBuildRun(workflowId) {
    return this.write('POST', '/v1/ciBuildRuns', {
      data: { type: 'ciBuildRuns', relationships: { workflow: { data: { type: 'ciWorkflows', id: workflowId } } } },
    });
  }

  // ---------- Sales Reports ----------

  /** Returns parsed rows, [] when Apple has no sales for that period (404), throws on other errors. */
  async salesReport(frequency, reportDate) {
    const vendor = String(this.account.vendorNumber || '').trim();
    if (!vendor) throw new AscError('No vendor number configured');
    try {
      const res = await this.request('GET', '/v1/salesReports', {
        accept: 'application/a-gzip',
        query: {
          'filter[frequency]': frequency,
          'filter[reportType]': 'SALES',
          'filter[reportSubType]': 'SUMMARY',
          'filter[vendorNumber]': vendor,
          'filter[reportDate]': reportDate,
          'filter[version]': '1_0',
        },
      });
      const raw = res.body[0] === 0x1f && res.body[1] === 0x8b ? zlib.gunzipSync(res.body) : res.body;
      return parseSales(raw.toString('utf8'));
    } catch (err) {
      if (err.status === 404) return [];
      throw err;
    }
  }
}

const KIND = {
  download: ['1', '1F', '1T', 'F1', '1E', '1EP', '1EU'],
  redownload: ['3', '3F', '3T', 'F3'],
  update: ['7', '7F', '7T', 'F7'],
  iap: ['IA1', 'IA9', 'IAY', 'IAC', 'FI1', 'IA1-M', 'IAY-M', 'IA9-M'],
};

function kindOf(type) {
  for (const [k, list] of Object.entries(KIND)) if (list.includes(type)) return k;
  return 'other';
}

function parseSales(tsv) {
  const lines = tsv.split(/\r?\n/).filter(Boolean);
  if (!lines.length) return [];
  const header = lines.shift().split('\t').map(h => h.trim());
  const col = name => header.indexOf(name);
  const idx = {
    apple: col('Apple Identifier'), parent: col('Parent Identifier'), sku: col('SKU'), title: col('Title'),
    type: col('Product Type Identifier'), units: col('Units'), proceeds: col('Developer Proceeds'),
    currency: col('Currency of Proceeds'), country: col('Country Code'), device: col('Device'),
  };
  const v = (f, i) => (i >= 0 && i < f.length ? f[i].trim() : '');
  return lines.map(line => {
    const f = line.split('\t');
    return {
      appleId: v(f, idx.apple), parentId: v(f, idx.parent), sku: v(f, idx.sku), title: v(f, idx.title),
      kind: kindOf(v(f, idx.type)), units: Math.round(Number(v(f, idx.units)) || 0),
      proceeds: Number(v(f, idx.proceeds)) || 0, currency: v(f, idx.currency),
      country: v(f, idx.country), device: v(f, idx.device),
    };
  }).filter(r => r.kind !== 'other');
}

/** Public iTunes lookup for artwork and ratings of live apps. */
async function storeLookup(ids, country = 'us') {
  const out = {};
  for (let i = 0; i < ids.length; i += 150) {
    const chunk = ids.slice(i, i + 150);
    try {
      const res = await rawRequest({ host: 'itunes.apple.com', path: `/lookup?id=${chunk.join(',')}&country=${country}&entity=software` });
      const json = JSON.parse(res.body.toString('utf8'));
      for (const r of json.results || []) {
        out[String(r.trackId)] = {
          artwork: r.artworkUrl512 || r.artworkUrl100 || null,
          rating: r.averageUserRating || null,
          ratingCount: r.userRatingCount || 0,
          url: r.trackViewUrl || null,
        };
      }
    } catch (e) { /* ignore lookup failures */ }
  }
  return out;
}

module.exports = { AscClient, AscError, makeToken, parseSales, storeLookup, kindOf };
