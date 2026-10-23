'use strict';

module.exports = {
  async getData({ homey }) {
    return homey.app.widgetData();
  },
};
