const { defineConfig, globalIgnores } = require('eslint/config');
const nodeConfig = require('@cordova/eslint-config/node');
const nodeTestConfig = require('@cordova/eslint-config/node-tests');
const browserConfig = require('@cordova/eslint-config/browser');

module.exports = defineConfig(
    [
        globalIgnores([
            'demo/platforms',
            'demo/plugins'
        ]),
        ...browserConfig.map(config => ({
            files: [
                'www/**/*.js',
                'tests/**/*.js'
            ],
            ...config,
            languageOptions: {
                ...(config?.languageOptions || {}),
                globals: {
                    ...(config.languageOptions?.globals || {}),
                    cordova: true,
                    WinJS: true,
                    describe: true,
                    jasmineRequire: true,
                    device: true,
                    require: true,
                    module: true,
                    exports: true
                }
            }
        })),
        ...nodeTestConfig.map(config => ({
            files: ['tests/**/*.js'],
            ...config
        })),
        ...nodeConfig.map(config => ({
            files: ['scripts/*.js'],
            ...config,
            rules: {
                ...(config.rules || {}),
                'space-before-function-paren': 'off'
            }
        }))
    ]
);
