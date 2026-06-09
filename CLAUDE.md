# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Cordova plugin (`cordova-plugin-eos`) that bridges Epic Online Services (EOS) into a Cordova/Capacitor webview app on **Android and iOS**. It exposes the EOS SDK's SDK-lifecycle, Auth, and Ecom (entitlements/offers/checkout) functionality to JavaScript. The EOS SDK itself is a binary dependency that is **not** checked into git — it is downloaded from Azure blob storage at build time (see SDK setup below).

## Architecture

The plugin is a layered bridge. Adding or changing a feature usually means touching the **same logical method in several layers**:

1. **JS API (`www/`)** — what app code calls. `eos.js` is the entry point, clobbered onto `window.plugins.eos`. It composes `auth.js` (`eos.auth.*`) and `ecom.js` (`eos.ecom.*`). Every method is a thin `cordova/exec` call wrapped in a Promise; errors are funneled through `rejectAsError` in `error.js` (which wraps them in `EOSError`). The string passed to `exec` (e.g. `'loginPortal'`) is the **action name** that the native side dispatches on.
2. **Native dispatch** — both platforms switch on the action string:
   - **Android**: `src/android/CordovaEOS.java` `execute()` (around line 342) routes each action to a `handle*` method. Java talks to the SDK through JNI `native` declarations (bottom of the file) implemented in `src/android/cpp/CordovaEOS/CordovaEOS.cpp`.
   - **iOS**: `src/ios/CordovaEOS.mm` (declared in `CordovaEOS.h`) implements one Obj-C method per action. The actual SDK calls live in `src/ios/EOSWrapper.mm` (`EOSWrapper.h`), a static Obj-C++ wrapper over the C `eos_sdk.h` API.
3. **EOS SDK** — the binary framework/AAR, resolved via `EOS_SDK_PATH`.

Async EOS results (login state changes, log messages, query results) are delivered back to JS via **persistent callbacks** (`PluginResult` with `setKeepCallback`). The plugin runs a **tick loop** (`startTickLoop`, ~10Hz) to pump the EOS SDK's update cycle while connected; `onConnect`/`onDisconnect` start/stop it.

So the canonical action set is mirrored in five places: `www/*.js`, `CordovaEOS.java` `execute()`, the Java `handle*` + `native` methods, `CordovaEOS.mm`, and `EOSWrapper.mm`. Keep them in sync. `types/index.d.ts` is the public TypeScript surface and is **maintained by hand** — update it when the JS API changes.

## Build & common commands

`EOS_SDK_PATH` must point at the unpacked SDK root (the dir containing `Include/`, `Bin/`) for native builds. Set it in your environment before any demo build.

```bash
npm i              # install dev deps (eslint, shx)
npm run lint       # eslint . — run before packaging
npm run lint:fix   # autofix
npm run package    # npm pack the plugin AND the tests → two .tgz files
```

`npm run package` produces `cordova-plugin-eos-<version>.tgz` and `cordova-plugin-eos-tests-<version>.tgz`. Keep `.npmignore` tight so the EOS SDK, demo, and tests don't leak into the published plugin package.

### EOS SDK download (requires Azure auth)

The SDK zip lives in Azure blob storage; downloading needs `az login` first. `<host>` is `windows` or `posix`:

```bash
npm run install-sdk:android:<host>   # download + unzip into eos-sdk/android/
npm run install-sdk:ios:<host>       # download + unzip into eos-sdk/ios/
```

The pinned SDK version is hardcoded in the `download-sdk:*` scripts in `package.json` — bump it there when upgrading.

### Demo app (also the test harness)

The `demo/` Cordova project consumes the packaged `.tgz` and runs the plugin's tests. It needs the config injected from 1Password (`op inject`, via `setup:demo:config`) and a `build.json` with your `APPLE_DEVELOPMENT_TEAM`. Typical loop, `<platform>` = `android`|`ios`:

```bash
npm run refresh:<platform>    # package + clean demo + setup + build
npm run restart:<platform>    # refresh + run on device
npm run run:android           # or run:ios — run without rebuilding plugin
```

`demo/` is gitignored output (`clean:demo` does `git clean -fxd`); never hand-edit files under `demo/platforms/` or `demo/plugins/` — they're regenerated.

## Tests

Tests are shipped as a **separate Cordova plugin** (`cordova-plugin-eos-tests`, defined in `tests/plugin.xml`) and run **inside the demo app on a real device/emulator** — there is no `npm test`. `tests/autoTests.js` holds Jasmine specs; `manualTests.js` + `ui.js` provide interactive buttons. There is no host-side unit test runner.

## Platform specifics

- **Android**: `src/android/build.gradle` enables ABI splits (`arm64-v8a`, `x86_64`) and 16KB page alignment (`ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES`, `-malign-double`). The login URL scheme (`eos_login_protocol_scheme`) is derived at build time from `ClientId` in `eos_config.json`. C++ is built with `-std=c++17`. If `cordova run` picks the wrong ABI (`INSTALL_FAILED_NO_MATCHING_ABIS`), install the matching `app-<abi>-debug.apk` manually — see README.
- **iOS**: the `before_plugin_install` hook `scripts/install_eos_framework.js` copies `EOSSDK.framework` from `EOS_SDK_PATH` into `src/ios/` and overwrites its `Info.plist` with `scripts/EOSSDK-Info.plist` (a patch to fix the minimum-OS-version TestFlight rejection). Uses `AuthenticationServices` for the login portal. `checkin:ios` copies edits made in Xcode back into `src/ios/`.

## Conventions

- License headers (Apache-2.0 ASF boilerplate) lead every source file.
- `sdk-patch/` holds reference copies of patched EOS sample files; `eos-sdk-old/` is legacy and not used by the build.
- CI is CircleCI (`.circleci/config.yml`); it builds the packages and demo, pulling secrets via the 1Password orb and the SDK via the Azure CLI orb. `plugin_version` is currently hardcoded there and must be bumped in lockstep with `package.json` / `plugin.xml`.
