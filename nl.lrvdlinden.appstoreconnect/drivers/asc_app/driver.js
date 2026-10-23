'use strict';

const Homey = require('homey');

module.exports = class AscAppDriver extends Homey.Driver {
  async onPairListDevices() {
    const app = this.homey.app;
    if (!app.getAccounts().length) throw new Error(this.homey.__('pair.no_account'));
    if (!Object.keys(app.data.apps).length) await app.refreshAll({ sales: false });
    return Object.values(app.data.apps)
      .sort((a, b) => a.name.localeCompare(b.name))
      .map(a => ({
        name: a.name,
        data: { id: a.id },
        store: { accountId: a.accountId, bundleId: a.bundleId },
      }));
  }
};
