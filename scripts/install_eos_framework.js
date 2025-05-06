#!/usr/bin/env node

var fs = require('fs');
var path = require('path');

function installEOSFramework (context) {
    const framework = path.join(process.env.EOS_SDK_PATH, 'Bin/IOS/EOSSDK.framework');
    console.log(`Copying ${framework}`);
    const destination = path.join(context.opts.plugin.pluginInfo.dir, 'src/ios/EOSSDK.framework');
    fs.cpSync(framework, destination, { recursive: true, force: true });
}

module.exports = installEOSFramework;
