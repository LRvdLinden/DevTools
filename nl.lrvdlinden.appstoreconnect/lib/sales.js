'use strict';

const fs = require('fs');
const path = require('path');

/** Dates in Pacific time, the timezone Apple uses for Sales Reports. */
function pacificToday() {
  let y; let m; let d;
  try {
    const s = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' }); // YYYY-MM-DD
    [y, m, d] = s.split('-').map(Number);
  } catch (e) { /* no full ICU */ }
  if (!y || !m || !d) {
    const pt = new Date(Date.now() - 8 * 3600000); // UTC-8 fallback
    [y, m, d] = [pt.getUTCFullYear(), pt.getUTCMonth() + 1, pt.getUTCDate()];
  }
  return new Date(Date.UTC(y, m - 1, d));
}
const day = d => d.toISOString().slice(0, 10);
const addDays = (d, n) => new Date(d.getTime() + n * 86400000);

/**
 * Fetches and caches Sales Reports. Reports of closed periods never change, so they are
 * cached on disk (/userdata) and fetched only once.
 */
class SalesStore {
  constructor({ dir = '/userdata/sales', log = () => {} } = {}) {
    this.dir = dir;
    this.log = log;
    this.memory = new Map();
    try { fs.mkdirSync(dir, { recursive: true }); } catch (e) { /* ignore */ }
  }

  _file(vendor, freq, date) { return path.join(this.dir, `${vendor}-${freq}-${date}.json`); }

  async report(client, freq, date, cacheable) {
    const vendor = String(client.account.vendorNumber || '').trim();
    const key = `${vendor}-${freq}-${date}`;
    if (this.memory.has(key)) return this.memory.get(key);
    const file = this._file(vendor, freq, date);
    if (cacheable) {
      try {
        const rows = JSON.parse(fs.readFileSync(file, 'utf8'));
        this.memory.set(key, rows);
        return rows;
      } catch (e) { /* not cached yet */ }
    }
    const rows = await client.salesReport(freq, date);
    if (cacheable) {
      try { fs.writeFileSync(file, JSON.stringify(rows)); } catch (e) { /* ignore */ }
      this.memory.set(key, rows);
    }
    return rows;
  }

  /** Daily reports for the last `days` days (oldest first). */
  async daily(client, days = 60) {
    const today = pacificToday();
    const dates = [];
    for (let i = days; i >= 1; i--) dates.push(addDays(today, -i));
    const out = [];
    for (let i = 0; i < dates.length; i += 6) {
      const chunk = dates.slice(i, i + 6);
      const res = await Promise.all(chunk.map(async d => {
        const age = Math.round((today - d) / 86400000);
        try {
          return { date: day(d), rows: await this.report(client, 'DAILY', day(d), age >= 4) };
        } catch (err) {
          if (err.status === 401 || err.status === 403) throw err;
          this.log(`Daily report ${day(d)} failed: ${err.message}`);
          return { date: day(d), rows: [] };
        }
      }));
      out.push(...res);
    }
    return out;
  }

  /** All-time totals: yearly reports for past years, monthly for this year, daily for this month. */
  async lifetime(client, dailyPeriods, firstYear) {
    const today = pacificToday();
    const year = today.getUTCFullYear();
    const month = today.getUTCMonth(); // 0-based
    const periods = [];
    for (let y = Math.max(2008, firstYear || year - 8); y < year; y++) {
      try { periods.push(await this.report(client, 'YEARLY', String(y), true)); } catch (e) { this.log(`Yearly ${y}: ${e.message}`); }
    }
    for (let m = 0; m < month; m++) {
      const label = `${year}-${String(m + 1).padStart(2, '0')}`;
      const monthEnd = new Date(Date.UTC(year, m + 1, 0));
      const settled = (today - monthEnd) / 86400000 > 10;
      let rows = [];
      try { rows = await this.report(client, 'MONTHLY', label, settled); } catch (e) { this.log(`Monthly ${label}: ${e.message}`); }
      if (!rows.length && !settled) {
        // Monthly report not ready yet: use the daily reports of that month.
        rows = dailyPeriods.filter(p => p.date.startsWith(label)).flatMap(p => p.rows);
      }
      periods.push(rows);
    }
    const thisMonth = `${year}-${String(month + 1).padStart(2, '0')}`;
    periods.push(dailyPeriods.filter(p => p.date.startsWith(thisMonth)).flatMap(p => p.rows));
    return periods.flat();
  }
}

function emptyStats() {
  return { yesterday: 0, last7: 0, prev7: 0, last30: 0, total: 0, updates30: 0, iap30: 0, proceeds30: 0, history: [] };
}

/**
 * Aggregates rows per app id. IAP rows are attributed to the parent app via its SKU.
 * Returns { perApp: {appId: stats}, portfolio: stats, currency }.
 */
function aggregate(apps, dailyPeriods, lifetimeRows) {
  const skuToApp = {};
  for (const a of apps) if (a.sku) skuToApp[a.sku] = a.id;
  const owner = r => (r.kind === 'iap' ? (skuToApp[r.parentId] || r.parentId) : r.appleId);
  const perApp = {};
  const portfolio = emptyStats();
  const currencies = {};
  for (const a of apps) perApp[a.id] = emptyStats();
  const n = dailyPeriods.length;

  dailyPeriods.forEach((p, i) => {
    const fromEnd = n - i; // 1 = yesterday
    const dayInstalls = {};
    let dayTotal = 0;
    for (const r of p.rows) {
      const id = owner(r);
      const s = perApp[id];
      if (!s) continue;
      const installs = r.kind === 'download' || r.kind === 'redownload' ? r.units : 0;
      if (installs) {
        dayInstalls[id] = (dayInstalls[id] || 0) + installs;
        dayTotal += installs;
      }
      if (fromEnd <= 30) {
        if (r.kind === 'update') { s.updates30 += r.units; portfolio.updates30 += r.units; }
        if (r.kind === 'iap') { s.iap30 += r.units; portfolio.iap30 += r.units; }
        const money = r.proceeds * r.units;
        if (money) {
          s.proceeds30 += money; portfolio.proceeds30 += money;
          currencies[r.currency] = (currencies[r.currency] || 0) + Math.abs(money);
        }
      }
    }
    for (const a of apps) {
      const v = dayInstalls[a.id] || 0;
      const s = perApp[a.id];
      s.history.push({ date: p.date, value: v });
      if (fromEnd === 1) s.yesterday = v;
      if (fromEnd <= 7) s.last7 += v;
      else if (fromEnd <= 14) s.prev7 += v;
      if (fromEnd <= 30) s.last30 += v;
    }
    portfolio.history.push({ date: p.date, value: dayTotal });
    if (fromEnd === 1) portfolio.yesterday = dayTotal;
    if (fromEnd <= 7) portfolio.last7 += dayTotal;
    else if (fromEnd <= 14) portfolio.prev7 += dayTotal;
    if (fromEnd <= 30) portfolio.last30 += dayTotal;
  });

  for (const r of lifetimeRows || []) {
    if (r.kind !== 'download' && r.kind !== 'redownload') continue;
    const s = perApp[owner(r)];
    if (s) s.total += r.units;
    portfolio.total += r.units;
  }
  const currency = Object.entries(currencies).sort((a, b) => b[1] - a[1])[0];
  return { perApp, portfolio, currency: currency ? currency[0] : 'USD' };
}

module.exports = { SalesStore, aggregate, pacificToday };
