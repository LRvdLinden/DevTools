'use strict';

const Homey = require('homey');

module.exports = class AscPortfolioDriver extends Homey.Driver {
  async onPairListDevices() {
    if (!this.homey.app.getAccounts().length) throw new Error(this.homey.__('pair.no_account'));
    return [{ name: this.homey.__('pair.portfolio_name'), data: { id: 'portfolio' } }];
  }
};
