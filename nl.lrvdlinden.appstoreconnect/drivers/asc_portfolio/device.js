'use strict';

const Homey = require('homey');

module.exports = class AscPortfolioDevice extends Homey.Device {
  async onInit() {
    await this.applyData(this.homey.app.portfolio(), this.homey.app.data.currency);
  }

  async set(cap, value) {
    if (!this.hasCapability(cap) || value === undefined || value === null) return;
    if (this.getCapabilityValue(cap) !== value) await this.setCapabilityValue(cap, value).catch(this.error);
  }

  async applyData(p) {
    await this.set('asc_apps_total', p.apps);
    await this.set('asc_apps_live', p.live);
    await this.set('asc_apps_review', p.inReview);
    await this.set('asc_apps_attention', p.attention);
    if (p.rating) await this.set('asc_rating', Math.round(p.rating * 10) / 10);
    if (p.salesDay) {
      await this.set('asc_downloads_yesterday', p.yesterday);
      await this.set('asc_downloads_7d', p.last7);
      await this.set('asc_downloads_30d', p.last30);
      await this.set('asc_downloads_total', p.total);
      await this.set('asc_updates_30d', p.updates30);
      await this.set('asc_proceeds_30d', Math.round(p.proceeds30 * 100) / 100);
    }
  }
};
