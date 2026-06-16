#!/usr/bin/env node
'use strict';

// Guards the version lockstep that `npm run setup:demo` depends on.
//
// `npm run package` produces `genvid-cordova-plugin-eos-<version>.tgz` (the
// @genvid-scoped plugin) and `cordova-plugin-eos-tests-<version>.tgz` (the
// unscoped tests harness). `demo/config.xml` pins
// those exact filenames (and a widget version). If `package.json` /
// `tests/package.json` are bumped without updating `demo/config.xml`, the CI
// jobs fail late and opaquely inside `cordova platform add`. This check fails
// fast and explains why.
//
// Adapted from genvid-holdings/cordova-plugin-marketplace@9b6721b
// (scripts/version-guard.js); stems substituted for this plugin.

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');

function versionOf (jsonPath) {
    return JSON.parse(fs.readFileSync(path.join(root, jsonPath), 'utf8')).version;
}

function firstMatch (text, re, label) {
    const m = text.match(re);
    if (!m) {
        console.error(`version-guard: could not find ${label} in demo/config.xml`);
        process.exit(1);
    }
    return m[1];
}

const pkgVersion = versionOf('package.json');
const testsVersion = versionOf('tests/package.json');

const configXml = fs.readFileSync(path.join(root, 'demo', 'config.xml'), 'utf8');
const widgetVersion = firstMatch(configXml, /<widget[^>]*\sversion="([^"]+)"/, 'widget version');
const pluginPin = firstMatch(configXml, /genvid-cordova-plugin-eos-([\d.]+)\.tgz/, 'plugin .tgz pin');
const testsPin = firstMatch(configXml, /cordova-plugin-eos-tests-([\d.]+)\.tgz/, 'tests .tgz pin');

const checks = [
    ['package.json', pkgVersion],
    ['tests/package.json', testsVersion],
    ['demo/config.xml widget version', widgetVersion],
    ['demo/config.xml plugin .tgz pin', pluginPin],
    ['demo/config.xml tests .tgz pin', testsPin]
];

const mismatch =
    pkgVersion !== testsVersion ||
    pkgVersion !== widgetVersion ||
    pkgVersion !== pluginPin ||
    testsVersion !== testsPin;

if (mismatch) {
    console.error('version-guard: version mismatch across sources:');
    for (const [name, value] of checks) {
        console.error(`  ${name}: ${value}`);
    }
    console.error('All must match so `npm run setup:demo` can resolve the packed .tgz files.');
    process.exit(1);
}

console.log(`version-guard: OK — all sources at ${pkgVersion}`);
