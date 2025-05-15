#!/usr/bin/env node

var fs = require('fs');
var path = require('path');

function installEOSFramework (context) {
    const framework = path.join(process.env.EOS_SDK_PATH, 'Bin/IOS/EOSSDK.framework');
    console.log(`Copying ${framework}`);
    const destination = path.join(context.opts.plugin.pluginInfo.dir, 'src/ios/EOSSDK.framework');
    fs.cpSync(framework, destination, { recursive: true, force: true });
    // Applied SDK patch
    // https://eoshelp.epicgames.com/s/article/When-running-a-test-flight-for-iOS-why-am-I-running-into-EOSSDK-framework-does-not-support-the-minimum-OS-Version-specified-in-the-Info-plist
    const pInfo = path.join(__dirname, 'EOSSDK-Info.plist');
    fs.cpSync(pInfo, path.join(destination, 'Info.plist'));
}

module.exports = installEOSFramework;
