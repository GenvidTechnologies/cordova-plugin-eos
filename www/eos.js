/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
 */

const argscheck = require('cordova/argscheck');
const exec = require('cordova/exec');
const { rejectAsError, EOSError } = require('./error');
const { EosEcom } = require('./ecom');
const { EosAuth } = require('./auth');

/**
 * @constructor
 */
function Eos () {
    this.SERVICE_NAME = 'EOS';
    this.available = true;
    this.initialized = false;
    this.sdkVersion = undefined;

    this.auth = new EosAuth(this);
    this.ecom = new EosEcom(this);
}

Eos.prototype.EOSError = EOSError;

Eos.prototype.getSDKVersion = function () {
    argscheck.checkArgs('', 'plugins.eos.getSDKVersion', arguments);
    return new Promise((resolve, reject) => {
        exec((r) => { resolve(r.sdkVersion); }, rejectAsError(reject), this.SERVICE_NAME, 'getSDKVersion', []);
    });
};

Eos.prototype.initializeSDK = function (sdkConfig, handler) {
    argscheck.checkArgs('OF', 'plugins.eos.ecom.initializeSDK', arguments);
    return new Promise((resolve, reject) => {
        let firstCall = true;
        function signalHandler (result) {
            if (firstCall) {
                firstCall = false;
                resolve();
            }
            handler(result);
        }
        exec(signalHandler, rejectAsError(reject), this.SERVICE_NAME, 'initializeSDK', [sdkConfig]);
    }).then(async () => {
        this.sdkVersion = await this.getSDKVersion();
        this.initialized = true;
    });
};

Eos.prototype.onConnect = function () {
    argscheck.checkArgs('', 'plugins.eos.onConnect', arguments);
    return new Promise((resolve, reject) => {
        exec(resolve, rejectAsError(reject), this.SERVICE_NAME, 'onConnect', []);
    });
};

Eos.prototype.onDisconnect = function () {
    argscheck.checkArgs('', 'plugins.eos.onDisconnect', arguments);
    return new Promise((resolve, reject) => {
        exec(resolve, rejectAsError(reject), this.SERVICE_NAME, 'onDisconnect', []);
    });
};

Eos.prototype.onLog = function (handler) {
    argscheck.checkArgs('F', 'plugins.eos.onLog', arguments);
    return new Promise((resolve, reject) => {
        let firstCall = true;
        function signalHandler (result) {
            if (firstCall) {
                firstCall = false;
                resolve();
            }
            if (handler) {
                handler(result);
            }
        }
        exec(signalHandler, rejectAsError(reject), this.SERVICE_NAME, 'logs', []);
    });
};

module.exports = new Eos();
