'use strict';

module.exports = {
  async test({ homey, body }) {
    return homey.app.testAccount(body || {});
  },
  async refresh({ homey }) {
    await homey.app.refreshAll({ sales: true });
    return homey.app.widgetData();
  },
  async status({ homey }) {
    const d = homey.app.widgetData();
    return { updated: d.updated, apps: d.apps.length, hasSales: d.hasSales, errors: d.errors };
  },
};
