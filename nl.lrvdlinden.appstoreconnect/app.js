'use strict';

const Homey = require('homey');
const { AscClient, storeLookup } = require('./lib/asc');
const { SalesStore, aggregate } = require('./lib/sales');
const status = require('./lib/status');

const SALES_INTERVAL = 3 * 60 * 60 * 1000;

module.exports = class AppStoreConnectApp extends Homey.App {

  async onInit() {
    this.lang = this.homey.i18n.getLanguage() || 'en';
    this.sales = new SalesStore({ dir: '/userdata/sales', log: (...a) => this.log(...a) });
    this.clients = new Map();
    this.data = { apps: {}, portfolio: null, currency: 'USD', updated: null, salesUpdated: null, errors: {} };
    this.memo = this.homey.settings.get('memo') || {};
    this.busy = false;

    this.registerFlowCards();
    this.registerWidgets();

    this.homey.settings.on('set', key => {
      if (key === 'accounts') {
        this.clients.clear();
        this.refreshAll({ sales: true }).catch(e => this.error(e));
      }
      if (key === 'pollMinutes') this.schedule();
    });

    this.schedule();
    this.homey.setTimeout(() => this.refreshAll({ sales: true }).catch(e => this.error(e)), 5000);
    this.log('App Store Connect started');
  }

  // ---------- Accounts ----------

  getAccounts() {
    return (this.homey.settings.get('accounts') || []).filter(a => a && a.issuerId && a.keyId && a.privateKey);
  }

  client(account) {
    const key = `${account.id}:${account.keyId}:${account.issuerId}`;
    if (!this.clients.has(key)) this.clients.set(key, new AscClient(account, { log: (...a) => this.log(...a) }));
    return this.clients.get(key);
  }

  async testAccount(account) {
    const client = new AscClient(account);
    const apps = await client.apps();
    let sales = null;
    if (account.vendorNumber) {
      try {
        const d = new Date(Date.now() - 3 * 86400000).toISOString().slice(0, 10);
        await client.salesReport('DAILY', d);
        sales = true;
      } catch (e) { sales = e.message; }
    }
    return { apps: apps.length, names: apps.slice(0, 5).map(a => a.name), sales };
  }

  // ---------- Scheduling ----------

  schedule() {
    if (this.statusTimer) this.homey.clearInterval(this.statusTimer);
    if (this.salesTimer) this.homey.clearInterval(this.salesTimer);
    const minutes = Math.max(5, Number(this.homey.settings.get('pollMinutes')) || 15);
    this.statusTimer = this.homey.setInterval(() => this.refreshAll({ sales: false }).catch(e => this.error(e)), minutes * 60000);
    this.salesTimer = this.homey.setInterval(() => this.refreshAll({ sales: true }).catch(e => this.error(e)), SALES_INTERVAL);
  }

  // ---------- Refresh ----------

  async refreshAll({ sales = false } = {}) {
    if (this.busy) return;
    this.busy = true;
    try {
      await this.refreshStatus();
      if (sales || !this.data.salesUpdated) {
        await this.refreshExtras();
        await this.refreshSales();
      }
      await this.publish();
    } finally {
      this.busy = false;
    }
  }

  async refreshStatus() {
    const accounts = this.getAccounts();
    const fresh = {};
    for (const account of accounts) {
      const client = this.client(account);
      try {
        const apps = await client.apps();
        for (let i = 0; i < apps.length; i += 4) {
          await Promise.all(apps.slice(i, i + 4).map(async app => {
            const [versions, builds, reviews, shots, crashes] = await Promise.all([
              client.versions(app.id).catch(() => null),
              client.builds(app.id, 3).catch(() => null),
              client.reviews(app.id, 10).catch(() => null),
              client.feedback(app.id, 'screenshot', 5).catch(() => null),
              client.feedback(app.id, 'crash', 5).catch(() => null),
            ]);
            const prev = this.data.apps[app.id] || {};
            const v = versions ? status.summarize(versions) : { live: prev.live, pending: prev.pending, headline: prev.headline };
            const build = builds ? builds[0] || null : prev.build;
            // Phased release of the live version. Once complete it no longer changes, so stop asking.
            let phased = null;
            if (v.live) {
              const done = prev.phased && prev.phased.versionId === v.live.id && prev.phased.state === 'COMPLETE';
              phased = done ? prev.phased : await client.phasedRelease(v.live.id).catch(() => prev.phased || null);
              if (phased) phased.versionId = v.live.id;
            }
            // Latest Xcode Cloud run per workflow (workflows are refreshed with the extras).
            const runs = {};
            for (const wf of (prev.workflows || []).filter(w => w.enabled)) {
              runs[wf.id] = await client.latestBuildRun(wf.id).catch(() => (prev.runs || {})[wf.id] || null);
            }
            fresh[app.id] = {
              ...prev,
              ...app,
              accountId: account.id,
              accountName: account.name || 'App Store Connect',
              live: v.live,
              pending: v.pending,
              headline: v.headline,
              build,
              buildState: status.buildState(build),
              reviews: reviews || prev.reviews || [],
              feedback: shots || prev.feedback || [],
              crashes: crashes || prev.crashes || [],
              phased,
              runs,
            };
          }));
        }
        delete this.data.errors[account.id];
      } catch (err) {
        this.error(`Account ${account.name}: ${err.message}`);
        this.data.errors[account.id] = err.message;
        for (const [id, a] of Object.entries(this.data.apps)) if (a.accountId === account.id) fresh[id] = a;
      }
    }
    const country = { nl: 'nl', de: 'de', fr: 'fr', it: 'it', sv: 'se', no: 'no', es: 'es', da: 'dk', ru: 'ru', pl: 'pl', ko: 'kr', ar: 'sa' }[this.lang] || 'us';
    const lookup = await storeLookup(Object.keys(fresh), country);
    const missing = Object.keys(fresh).filter(id => !lookup[id]);
    if (missing.length) Object.assign(lookup, await storeLookup(missing, 'us'));
    for (const [id, a] of Object.entries(fresh)) {
      const l = lookup[id];
      a.artwork = (l && l.artwork) || (a.build && a.build.iconUrl) || a.artwork || null;
      a.rating = l ? l.rating : a.rating || null;
      a.ratingCount = l ? l.ratingCount : a.ratingCount || 0;
      a.storeUrl = (l && l.url) || `https://apps.apple.com/app/id${id}`;
    }
    this.data.apps = fresh;
    this.data.updated = new Date().toISOString();
  }

  /** TestFlight installs/testers and Xcode Cloud workflows: heavier calls, so only every few hours. */
  async refreshExtras() {
    const cache = this.buildUsage || (this.buildUsage = {});
    for (const account of this.getAccounts()) {
      const client = this.client(account);
      const apps = Object.values(this.data.apps).filter(a => a.accountId === account.id);
      for (const a of apps) {
        try {
          const builds = await client.builds(a.id, 100);
          const total = { installs: 0, sessions: 0, crashes: 0, feedback: 0, invites: 0 };
          for (let i = 0; i < builds.length; i += 6) {
            await Promise.all(builds.slice(i, i + 6).map(async b => {
              let u = cache[b.id];
              if (!u || !b.expired) u = await client.betaUsage(b.id).catch(() => cache[b.id] || null);
              if (!u) return;
              cache[b.id] = u;
              for (const k of Object.keys(total)) total[k] += u[k] || 0;
            }));
          }
          total.testers = await client.betaTesterCount(a.id).catch(() => (a.testflight || {}).testers || 0);
          a.testflight = total;
        } catch (err) { this.log(`TestFlight ${a.name}: ${err.message}`); }
        a.workflows = await client.ciWorkflows(a.id).catch(() => a.workflows || []);
      }
    }
  }

  async refreshSales() {
    const accounts = this.getAccounts().filter(a => String(a.vendorNumber || '').trim());
    const allApps = Object.values(this.data.apps);
    let portfolio = null;
    let currency = 'USD';
    for (const account of accounts) {
      const client = this.client(account);
      const apps = allApps.filter(a => a.accountId === account.id);
      try {
        const daily = await this.sales.daily(client, 60);
        const lifetime = await this.sales.lifetime(client, daily, account.firstYear ? Number(account.firstYear) : undefined);
        const agg = aggregate(apps, daily, lifetime);
        for (const a of apps) a.stats = agg.perApp[a.id];
        currency = agg.currency;
        portfolio = portfolio ? mergeStats(portfolio, agg.portfolio) : agg.portfolio;
        delete this.data.errors[`sales:${account.id}`];
      } catch (err) {
        this.error(`Sales ${account.name}: ${err.message}`);
        this.data.errors[`sales:${account.id}`] = err.message;
      }
    }
    if (portfolio) {
      this.data.portfolio = portfolio;
      this.data.currency = currency;
      this.data.salesUpdated = new Date().toISOString();
    }
  }

  // ---------- Publish to devices, flows and widgets ----------

  async publish() {
    const updates = [];
    const firstRun = !this.memo.__init;
    const apps = Object.values(this.data.apps);
    const appDevices = this.homey.drivers.getDriver('asc_app').getDevices();
    const deviceFor = id => appDevices.find(d => d.getData().id === id);

    for (const a of apps) {
      const m = this.memo[a.id] || {};
      const device = deviceFor(a.id);
      if (device) updates.push(device.applyData(a, this.data.currency).catch(e => this.error(e)));
      if (!firstRun && m.headline !== undefined) this.fireAppTriggers(a, m, device);
      this.memo[a.id] = {
        headline: a.headline,
        live: a.live ? a.live.version : null,
        buildId: a.build ? a.build.id : null,
        buildState: a.buildState,
        reviewId: a.reviews[0] ? a.reviews[0].id : m.reviewId || null,
        rating: a.rating,
        feedbackId: a.feedback && a.feedback[0] ? a.feedback[0].id : m.feedbackId || null,
        crashId: a.crashes && a.crashes[0] ? a.crashes[0].id : m.crashId || null,
        phased: a.phased ? `${a.phased.state}:${a.phased.day}` : null,
        runs: Object.fromEntries(Object.entries(a.runs || {}).filter(([, r]) => r).map(([id, r]) => [id, `${r.id}:${r.progress}`])),
        yesterday: a.stats ? a.stats.yesterday : m.yesterday,
        salesDay: a.stats && a.stats.history.length ? a.stats.history[a.stats.history.length - 1].date : m.salesDay,
      };
    }

    const p = this.portfolio();
    for (const device of this.homey.drivers.getDriver('asc_portfolio').getDevices()) {
      updates.push(device.applyData(p, this.data.currency).catch(e => this.error(e)));
    }
    const pm = this.memo.__portfolio || {};
    if (!firstRun && p.salesDay && pm.salesDay && p.salesDay !== pm.salesDay) {
      const tokens = { yesterday: p.yesterday, last7: p.last7, total: p.total };
      this.cards.anyTotal.trigger(tokens).catch(e => this.error(e));
      for (const d of this.homey.drivers.getDriver('asc_portfolio').getDevices()) {
        this.cards.portfolioUpdated.trigger(d, tokens).catch(e => this.error(e));
      }
    }
    this.memo.__portfolio = { salesDay: p.salesDay, total: p.total };
    this.memo.__init = true;
    await Promise.all(updates);
    this.homey.settings.set('memo', this.memo);
    try { this.homey.api.realtime('update', { updated: this.data.updated }); } catch (e) { /* no listeners */ }
  }

  fireAppTriggers(a, m, device) {
    const name = a.name;
    const dev = (card, tokens) => device && card.trigger(device, tokens).catch(e => this.error(e));
    const any = (card, tokens) => card.trigger({ app: name, ...tokens }).catch(e => this.error(e));
    const L = s => status.label(s, this.lang);

    if (a.headline !== m.headline) {
      const tokens = { status: L(a.headline), previous: L(m.headline), version: a.pending ? a.pending.version : (a.live ? a.live.version : '') };
      dev(this.cards.statusChanged, tokens);
      any(this.cards.anyStatus, tokens);
      if (status.REVIEW.has(a.headline) && !status.REVIEW.has(m.headline)) { dev(this.cards.enteredReview, { version: tokens.version }); any(this.cards.anyReview, { version: tokens.version }); }
      if (status.REJECTED.has(a.headline)) { dev(this.cards.rejected, { version: tokens.version }); any(this.cards.anyRejected, { version: tokens.version }); }
      if (a.headline === 'READY_FOR_DISTRIBUTION') dev(this.cards.readyForDistribution, { version: tokens.version });
      if (a.headline === 'PENDING_DEVELOPER_RELEASE') dev(this.cards.pendingRelease, { version: tokens.version });
    }
    const liveVersion = a.live ? a.live.version : null;
    if (liveVersion && liveVersion !== m.live) {
      dev(this.cards.newLive, { version: liveVersion });
      any(this.cards.anyLive, { version: liveVersion });
    }
    if (a.build && a.build.id !== m.buildId) {
      dev(this.cards.newBuild, { build: a.build.number || '', version: a.build.version || '' });
    }
    if (a.build && a.buildState !== m.buildState && a.buildState && a.build.processingState === 'VALID' && m.buildState === 'PROCESSING') {
      dev(this.cards.buildReady, { build: a.build.number || '', version: a.build.version || '' });
    }
    const newest = a.reviews[0];
    if (newest && newest.id !== m.reviewId) {
      const known = a.reviews.findIndex(r => r.id === m.reviewId);
      const fresh = known === -1 ? [newest] : a.reviews.slice(0, known);
      for (const r of fresh.reverse()) {
        const tokens = { rating: r.rating, title: r.title, body: r.body, author: r.author, territory: r.territory, review_id: r.id };
        dev(this.cards.newReview, tokens);
        any(this.cards.anyNewReview, tokens);
      }
    }
    const newItems = (list, lastId) => {
      if (!list || !list.length || list[0].id === lastId) return [];
      const known = list.findIndex(x => x.id === lastId);
      return (lastId === undefined ? [] : (known === -1 ? [list[0]] : list.slice(0, known))).reverse();
    };
    for (const f of newItems(a.feedback, m.feedbackId)) {
      const tokens = { comment: f.comment, tester: f.tester, device: f.device, os_version: f.osVersion, build: f.build };
      dev(this.cards.newFeedback, tokens);
      any(this.cards.anyFeedback, tokens);
    }
    for (const f of newItems(a.crashes, m.crashId)) {
      const tokens = { comment: f.comment, tester: f.tester, device: f.device, os_version: f.osVersion, build: f.build };
      dev(this.cards.newCrash, tokens);
      any(this.cards.anyCrash, tokens);
    }
    const phasedKey = a.phased ? `${a.phased.state}:${a.phased.day}` : null;
    if (a.phased && phasedKey !== m.phased && m.phased !== undefined) {
      dev(this.cards.phasedChanged, { state: phasedLabel(a.phased, this.homey), day: a.phased.day || 0, percentage: phasedPercent(a.phased) });
    }
    for (const [wfId, r] of Object.entries(a.runs || {})) {
      if (!r || r.progress !== 'COMPLETE') continue;
      const before = (m.runs || {})[wfId];
      if (before === undefined || before === `${r.id}:COMPLETE`) continue;
      const wf = (a.workflows || []).find(w => w.id === wfId);
      dev(this.cards.ciFinished, {
        workflow: wf ? wf.name : '', number: r.number || 0,
        result: status.label(`CI_${r.result}`, this.lang), succeeded: r.result === 'SUCCEEDED',
      });
    }
    if (a.rating && m.rating && Math.abs(a.rating - m.rating) >= 0.01) {
      dev(this.cards.ratingChanged, { rating: Math.round(a.rating * 100) / 100, previous: Math.round(m.rating * 100) / 100 });
    }
    if (a.stats && a.stats.history.length) {
      const day = a.stats.history[a.stats.history.length - 1].date;
      if (m.salesDay && day !== m.salesDay) {
        const tokens = { yesterday: a.stats.yesterday, last7: a.stats.last7, total: a.stats.total };
        dev(this.cards.downloadsUpdated, tokens);
        if (typeof m.yesterday === 'number' && a.stats.yesterday < m.yesterday) {
          dev(this.cards.downloadsDropped, { yesterday: a.stats.yesterday, previous: m.yesterday });
        }
      }
    }
  }

  phasedText(p) { return phasedLabel(p, this.homey); }

  portfolio() {
    const apps = Object.values(this.data.apps);
    const p = this.data.portfolio || { yesterday: 0, last7: 0, prev7: 0, last30: 0, total: 0, updates30: 0, iap30: 0, proceeds30: 0, history: [] };
    const rated = apps.filter(a => a.rating && a.ratingCount);
    const count = rated.reduce((s, a) => s + a.ratingCount, 0);
    return {
      ...p,
      apps: apps.length,
      live: apps.filter(a => a.live).length,
      inReview: apps.filter(a => status.REVIEW.has(a.headline)).length,
      attention: apps.filter(a => needsAttention(a)).length,
      rating: count ? rated.reduce((s, a) => s + a.rating * a.ratingCount, 0) / count : null,
      testflightInstalls: apps.reduce((s, a) => s + (a.testflight ? a.testflight.installs : 0), 0),
      salesDay: p.history.length ? p.history[p.history.length - 1].date : null,
    };
  }

  // ---------- Flow cards ----------

  registerFlowCards() {
    const f = this.homey.flow;
    const dt = id => f.getDeviceTriggerCard(id);
    this.cards = {
      statusChanged: dt('status_changed'),
      enteredReview: dt('entered_review'),
      rejected: dt('review_rejected'),
      readyForDistribution: dt('ready_for_distribution'),
      pendingRelease: dt('pending_release'),
      newLive: dt('new_live_version'),
      newBuild: dt('new_build'),
      buildReady: dt('build_processed'),
      newReview: dt('new_customer_review'),
      ratingChanged: dt('rating_changed'),
      downloadsUpdated: dt('downloads_updated'),
      downloadsDropped: dt('downloads_dropped'),
      portfolioUpdated: dt('portfolio_downloads_updated'),
      newFeedback: dt('new_testflight_feedback'),
      newCrash: dt('new_testflight_crash'),
      phasedChanged: dt('phased_release_changed'),
      ciFinished: dt('xcode_cloud_build_finished'),
      anyFeedback: f.getTriggerCard('any_new_testflight_feedback'),
      anyCrash: f.getTriggerCard('any_new_testflight_crash'),
      anyStatus: f.getTriggerCard('any_status_changed'),
      anyReview: f.getTriggerCard('any_entered_review'),
      anyRejected: f.getTriggerCard('any_review_rejected'),
      anyLive: f.getTriggerCard('any_new_live_version'),
      anyNewReview: f.getTriggerCard('any_new_customer_review'),
      anyTotal: f.getTriggerCard('total_downloads_updated'),
    };

    const rec = args => this.data.apps[args.device.getData().id] || {};
    const cond = (id, fn) => f.getConditionCard(id).registerRunListener(async args => fn(rec(args), args));
    cond('is_live', a => !!a.live);
    cond('is_in_review', a => status.REVIEW.has(a.headline));
    cond('has_pending_version', a => !!a.pending);
    cond('downloads_yesterday_above', (a, args) => (a.stats ? a.stats.yesterday : 0) > args.number);
    cond('downloads_7d_above', (a, args) => (a.stats ? a.stats.last7 : 0) > args.number);
    cond('downloads_total_above', (a, args) => (a.stats ? a.stats.total : 0) > args.number);
    cond('rating_above', (a, args) => (a.rating || 0) > args.number);
    cond('live_older_than', (a, args) => {
      if (!a.live || !a.live.created) return false;
      return (Date.now() - new Date(a.live.created).getTime()) / 86400000 > args.days;
    });
    cond('phased_release_active', a => !!a.phased && a.phased.state === 'ACTIVE');
    cond('testflight_installs_above', (a, args) => (a.testflight ? a.testflight.installs : 0) > args.number);
    f.getConditionCard('portfolio_downloads_yesterday_above').registerRunListener(async args => this.portfolio().yesterday > args.number);
    f.getConditionCard('portfolio_any_in_review').registerRunListener(async () => this.portfolio().inReview > 0);

    f.getActionCard('refresh').registerRunListener(async () => { await this.refreshAll({ sales: true }); return true; });
    f.getActionCard('refresh_app').registerRunListener(async () => { await this.refreshAll({ sales: false }); return true; });
    f.getActionCard('release_version').registerRunListener(async args => {
      const a = rec(args);
      if (!a.pending || a.pending.state !== 'PENDING_DEVELOPER_RELEASE') {
        throw new Error(this.homey.__('errors.no_pending_release'));
      }
      const account = this.getAccounts().find(x => x.id === a.accountId);
      await this.client(account).releaseVersion(a.pending.id);
      await this.refreshAll({ sales: false });
      return true;
    });
    f.getActionCard('phased_release_control').registerRunListener(async args => {
      const a = rec(args);
      if (!a.phased) throw new Error(this.homey.__('errors.no_phased_release'));
      const account = this.getAccounts().find(x => x.id === a.accountId);
      await this.client(account).setPhasedRelease(a.phased.id, args.action);
      await this.refreshAll({ sales: false });
      return true;
    });
    const startBuild = f.getActionCard('start_xcode_cloud_build');
    startBuild.registerArgumentAutocompleteListener('workflow', async (query, args) => {
      const a = rec(args);
      const q = String(query || '').toLowerCase();
      return (a.workflows || []).filter(w => w.enabled && (!q || w.name.toLowerCase().includes(q))).map(w => ({ id: w.id, name: w.name }));
    });
    startBuild.registerRunListener(async args => {
      const a = rec(args);
      const account = this.getAccounts().find(x => x.id === a.accountId);
      if (!account || !args.workflow || !args.workflow.id) throw new Error(this.homey.__('errors.no_workflow'));
      await this.client(account).startBuildRun(args.workflow.id);
      return true;
    });
    f.getActionCard('reply_to_review').registerRunListener(async args => {
      const a = rec(args);
      const account = this.getAccounts().find(x => x.id === a.accountId);
      if (!account) throw new Error('Account not found');
      await this.client(account).respondToReview(String(args.review_id).trim(), args.text);
      return true;
    });
  }

  // ---------- Widgets ----------

  registerWidgets() {
    const listener = async query => {
      const q = String(query || '').toLowerCase();
      const all = [{ id: '', name: this.homey.__('widget.all_apps') }];
      for (const a of Object.values(this.data.apps)) {
        all.push({ id: a.id, name: a.name, description: status.label(a.headline, this.lang), image: a.artwork || undefined });
      }
      return all.filter(i => !q || i.name.toLowerCase().includes(q));
    };
    try {
      this.homey.dashboards.getWidget('downloads').registerSettingAutocompleteListener('app', listener);
    } catch (e) { this.error('Widget autocomplete', e.message); }
  }

  /** Data for the dashboard widgets (same snapshot idea as the iOS widgets). */
  widgetData() {
    const apps = Object.values(this.data.apps).map(a => ({
      id: a.id,
      name: a.name,
      icon: a.artwork,
      state: a.headline,
      label: status.label(a.headline, this.lang),
      color: status.color(a.headline),
      live: a.live ? a.live.version : null,
      next: a.pending ? a.pending.version : null,
      build: a.build ? a.build.number : null,
      buildState: a.buildState,
      rating: a.rating,
      ratingCount: a.ratingCount,
      inReview: status.REVIEW.has(a.headline),
      attention: needsAttention(a),
      stats: a.stats || null,
    })).sort((x, y) => ((y.stats ? y.stats.last30 : -1) - (x.stats ? x.stats.last30 : -1)) || x.name.localeCompare(y.name));
    return {
      lang: this.lang,
      currency: this.data.currency,
      updated: this.data.updated,
      hasSales: !!this.data.portfolio,
      portfolio: this.portfolio(),
      apps,
      errors: Object.values(this.data.errors),
    };
  }
};

const PHASED_PERCENT = [1, 2, 5, 10, 20, 50, 100];
function phasedPercent(p) {
  if (!p) return 0;
  if (p.state === 'COMPLETE') return 100;
  return PHASED_PERCENT[Math.max(1, Math.min(7, p.day || 1)) - 1];
}
function phasedLabel(p, homey) {
  if (!p) return '—';
  const base = homey.__(`phased.${p.state}`) || p.state;
  return p.state === 'ACTIVE' || p.state === 'PAUSED' ? `${base} · ${phasedPercent(p)}%` : base;
}

function needsAttention(a) {
  return status.REJECTED.has(a.headline) || a.headline === 'PENDING_DEVELOPER_RELEASE'
    || a.headline === 'READY_FOR_DISTRIBUTION' || a.buildState === 'MISSING_EXPORT_COMPLIANCE';
}

function mergeStats(a, b) {
  const out = { ...a };
  for (const k of ['yesterday', 'last7', 'prev7', 'last30', 'total', 'updates30', 'iap30', 'proceeds30']) out[k] = (a[k] || 0) + (b[k] || 0);
  const byDate = {};
  for (const p of [...a.history, ...b.history]) byDate[p.date] = (byDate[p.date] || 0) + p.value;
  out.history = Object.keys(byDate).sort().map(date => ({ date, value: byDate[date] }));
  return out;
}
