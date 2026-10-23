'use strict';

const Homey = require('homey');
const status = require('../../lib/status');

module.exports = class AscAppDevice extends Homey.Device {
  async onInit() {
    const rec = this.homey.app.data.apps[this.getData().id];
    if (rec) await this.applyData(rec, this.homey.app.data.currency);
  }

  async set(cap, value) {
    if (!this.hasCapability(cap) || value === undefined || value === null) return;
    if (this.getCapabilityValue(cap) !== value) await this.setCapabilityValue(cap, value).catch(this.error);
  }

  /** Called by the app after every refresh. */
  async applyData(a, currency) {
    const lang = this.homey.app.lang;
    if (this.getAvailable() === false) await this.setAvailable().catch(this.error);
    await this.set('asc_status', status.label(a.headline, lang));
    await this.set('asc_version_live', a.live ? a.live.version : '—');
    await this.set('asc_version_next', a.pending ? `${a.pending.version} · ${status.label(a.pending.state, lang)}` : '—');
    await this.set('asc_build', a.build ? `${a.build.version || ''} (${a.build.number})`.trim() : '—');
    await this.set('asc_build_state', a.buildState ? status.label(a.buildState, lang) : '—');
    await this.set('asc_in_review', status.REVIEW.has(a.headline));
    if (a.rating) await this.set('asc_rating', Math.round(a.rating * 10) / 10);
    await this.set('asc_rating_count', a.ratingCount || 0);
    if (a.stats) {
      await this.set('asc_downloads_yesterday', a.stats.yesterday);
      await this.set('asc_downloads_7d', a.stats.last7);
      await this.set('asc_downloads_30d', a.stats.last30);
      await this.set('asc_downloads_total', a.stats.total);
      await this.set('asc_updates_30d', a.stats.updates30);
      await this.set('asc_proceeds_30d', Math.round(a.stats.proceeds30 * 100) / 100);
    }
    await this.setSettings({ bundle_id: a.bundleId || '', account: a.accountName || '', currency: currency || '' }).catch(() => {});
  }
};
