const { updateStatus } = require('./testAuthService');

exports.innerHTML = `
    <div id="initialized">press Refresh to update...</div>
    <div id="available">press Refresh to update...</div>
`;

const onLoginChanged = async function (result) {
    console.log(`login changed: ${result.status}`);
    try {
        await updateStatus(result.status);
    } catch (err) {
        console.error(`Error on login changed: ${err.message}`);
    }
};

const updateSdkStatus = () => {
    const eos = window.plugins.eos;
    document.getElementById('available').innerText = eos.available ? 'available' : 'unavailable';
    document.getElementById('initialized').innerText = eos.initialized ? 'initialized' : 'uninitialized';
};

const testSdkApi = function (createActionButton) {
    let loggedOn = false;
    createActionButton(
        'Toggle logs',
        async function () {
            try {
                const eos = window.plugins.eos;
                loggedOn = !loggedOn;
                if (loggedOn) {
                    eos.onLog((log) => console.log(`native-log: ${log.message}`));
                    // switch off:
                } else {
                    eos.onLog();
                }
            } catch (err) {
                console.error(`Logs toggle error: ${err.message}`);
            }
        },
        'sdk'
    );

    createActionButton(
        'Initialize',
        async function () {
            try {
                const eos = window.plugins.eos;
                const response = await fetch('../eos_config.json');
                const SDKConfig = await response.json();
                await eos.initializeSDK(SDKConfig, (result) => onLoginChanged(result));
                updateSdkStatus();
                console.log('Initialized');
            } catch (err) {
                console.error(`Initialize error: ${err.message}`);
            }
        },
        'sdk'
    );

    createActionButton(
        'Online',
        async function () {
            try {
                const eos = window.plugins.eos;
                if (!eos.initialized) {
                    console.warn('You must initialized the SDK first.');
                } else {
                    await eos.onConnect();
                    console.log('Connected');
                    updateSdkStatus();
                }
            } catch (err) {
                console.error(`Online error: ${err.message}`);
            }
        },
        'sdk'
    );

    createActionButton(
        'Offline',
        async function () {
            try {
                const eos = window.plugins.eos;
                if (!eos.initialized) {
                    console.warn('You must initialized the SDK first.');
                } else {
                    await eos.onDisconnect();
                    console.log('Disconnected');
                    updateSdkStatus();
                }
            } catch (err) {
                console.error(`Offline error: ${err.message}`);
            }
        },
        'sdk'
    );

    createActionButton(
        'Refresh',
        async function () {
            console.log('Refreshing...');
            updateSdkStatus();
        },
        'sdk'
    );
};

exports.setup = testSdkApi;
