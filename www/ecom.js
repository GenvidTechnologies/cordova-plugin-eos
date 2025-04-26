const argscheck = require('cordova/argscheck');
const exec = require('cordova/exec');
const { rejectAsError } = require('./error');

function EosEcom (eos) {
    this.eos = eos;
}

EosEcom.prototype.queryEntitlements = function () {
    argscheck.checkArgs('', 'plugins.eos.ecom.queryEntitlements', arguments);
    return new Promise((resolve, reject) => {
        exec(r => resolve(r.entitlements), rejectAsError(reject), this.eos.SERVICE_NAME, 'queryEntitlements', []);
    });
};

EosEcom.prototype.queryOffers = function () {
    argscheck.checkArgs('', 'plugins.eos.ecom.queryOffers', arguments);
    return new Promise((resolve, reject) => {
        exec(r => resolve(r.offers), rejectAsError(reject), this.eos.SERVICE_NAME, 'queryOffers', []);
    });
};

EosEcom.prototype.checkout = function (offerIds) {
    argscheck.checkArgs('A', 'plugins.eos.ecom.checkout', arguments);
    return new Promise((resolve, reject) => {
        exec(resolve, rejectAsError(reject), this.eos.SERVICE_NAME, 'checkout', [offerIds]);
    });
};

exports.EosEcom = EosEcom;
