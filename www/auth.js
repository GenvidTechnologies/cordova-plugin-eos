const argscheck = require('cordova/argscheck');
const exec = require('cordova/exec');
const { rejectAsError } = require('./error');

function EosAuth (eos) {
    this.eos = eos;
}

EosAuth.prototype.isLoggedIn = function () {
    argscheck.checkArgs('', 'plugins.eos.auth.isLoggedIn', arguments);
    return new Promise((resolve, reject) => {
        exec((r) => resolve(r.isLoggedIn), rejectAsError(reject), this.eos.SERVICE_NAME, 'isLoggedIn', []);
    });
};

EosAuth.prototype.getUsername = function () {
    argscheck.checkArgs('', 'plugins.eos.auth.getUsername', arguments);
    return new Promise((resolve, reject) => {
        exec((r) => resolve(r.username), rejectAsError(reject), this.eos.SERVICE_NAME, 'getUsername', []);
    });
};

EosAuth.prototype.getAccountId = function () {
    argscheck.checkArgs('', 'plugins.eos.auth.getAccountId', arguments);
    return new Promise((resolve, reject) => {
        exec((r) => resolve(r.accountId), rejectAsError(reject), this.eos.SERVICE_NAME, 'getAccountId', []);
    });
};

EosAuth.prototype.getAuthToken = function () {
    argscheck.checkArgs('', 'plugins.eos.auth.getAuthToken', arguments);
    return new Promise((resolve, reject) => {
        exec(r => resolve(r.authToken), rejectAsError(reject), this.eos.SERVICE_NAME, 'getAuthToken', []);
    });
};

EosAuth.prototype.login = function (persistent) {
    // argscheck does not support boolean type
    argscheck.checkArgs('*', 'plugins.eos.auth.login', arguments);
    return new Promise((resolve, reject) => {
        exec(r => resolve(r.result), rejectAsError(reject), this.eos.SERVICE_NAME, persistent ? 'loginPersistent' : 'loginPortal', []);
    });
};

EosAuth.prototype.logout = function () {
    argscheck.checkArgs('', 'plugins.eos.auth.logout', arguments);
    return new Promise((resolve, reject) => {
        exec(r => resolve(r.result), rejectAsError(reject), this.eos.SERVICE_NAME, 'logout', []);
    });
};

exports.EosAuth = EosAuth;
