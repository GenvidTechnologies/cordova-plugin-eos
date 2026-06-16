# Cordova Epic Online Services Plugin

Published on npm as [`@genvid/cordova-plugin-eos`](https://www.npmjs.com/package/@genvid/cordova-plugin-eos)
with build provenance.

## Installation

```bash
cordova plugin add @genvid/cordova-plugin-eos
```

The EOS SDK binary is not bundled: set `EOS_SDK_PATH` to your unpacked EOS SDK
root before building so the plugin's install hook can resolve the native
framework/AAR.

## Development

### File structures

* `plugin.xml`: The plugin configuration file
* `src/`
  * `android/`: Android source code
  * `ios/`: iOS source code
* `www/`: Web source code
* `tests/`: Node Project Plugin Tests
* `types/`: Some type definitions (manually update)
* `demo/`: Node Demo project also use for testing
* `eos-sdk/`: Use to populate the EOS SDK by default

### How to build the plugin

```bash
npm i
npm run lint
npm run package
```

This will create two package:

* `genvid-cordova-plugin-eos-<version>.tgz` for the plugin (the `@genvid`-scoped npm package)
* `cordova-plugin-eos-tests-<version>.tgz` for the tests

#### Notice

Please, maintain the `.npmignore` consistently to avoid
distributing unnecessary files in the packages.

### How to build and run the test demo

After having build the packages:

```bash
npm run install-sdk:<platform>:<host>
npm run setup:demo:<platform>
npm run build:demo:<platform>
```

where `host` is replaced with either `windows` (if you're on Windows) or `posix` (MacOS, Linux),
and `<platform>` is replaced with either `android` or `ios`

Then you can run the application:

```bash
npm run run:demo:<platform>
```

To clean everything and rebuild, you can do:

```bash
npm run refresh:demo:<platform>
```

### Manual installation and running for Android

Sometimes, cordova doesn't select the right ABI to upload.  You will get an error like:

```
Using apk: C:\repos\cordova-plugin-eos\demo\platforms\android\app\build\outputs\apk\debug\app-armeabi-v7a-debug.apk
Package name: com.genvidtech.eosdemo
Command failed with exit code 1: adb -s 38110DLJH000N8 install -r C:\repos\cordova-plugin-eos\demo\platforms\android\app\build\outputs\apk\debug\app-armeabi-v7a-debug.apk
adb: failed to install C:\repos\cordova-plugin-eos\demo\platforms\android\app\build\outputs\apk\debug\app-armeabi-v7a-debug.apk: Failure [INSTALL_FAILED_NO_MATCHING_ABIS: INSTALL_FAILED_NO_MATCHING_ABIS: Failed to extract native libraries, res=-113]
```

Here what to do:

```powershell
# install the right APK
abd install -r .\demo\platforms\android\build\outputs\apk\debug\app-{abi of your android device}-debug.apk
# start the application on the device
adb shell am start -n com.genvidtech.eosdemo/com.genvidtech.eosdemo.MainActivity
# output logs
adb logcat --pid=$(adb shell pidof -s com.genvidtech.eosdemo) | tee eosdemo.log
```
