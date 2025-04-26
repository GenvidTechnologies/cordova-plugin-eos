const { getElementByNameFunction, hookCopyInnerText } = require('./ui');

exports.innerHTML = `
    <div>State: <span id="state"></span></div>
    <div>Username: <span id="username"></span> <button id="copyusername">Copy</button></div>
    <div>Account ID: <span id="accountId"></span> <button id="copyaccountId">Copy</button></div>
    <details>
      <summary>Token:</summary>
      <details>
        <summary>Encoded:</summary>
        <pre><code id="token"></code></pre>
        <button id="copytoken">Copy</button></br>
      </details>
      <details>
        <summary>Decoded:</summary>
        <pre><code id="jwt"></code></pre>
        <button id="copyjwt">Copy</button>
      </details>
    </details>
`;

const decodeToken = function (token) {
    const [header, claim, signature] = token.split('.');
    return {
        header: JSON.parse(atob(header)),
        claim: JSON.parse(atob(claim)),
        signature
    };
};

const getJwtElement = getElementByNameFunction('jwt', [hookCopyInnerText]);

const getTokenElement = getElementByNameFunction('token', [hookCopyInnerText]);

const getUsernameElement = getElementByNameFunction('username', [hookCopyInnerText]);

const getAccountIdElement = getElementByNameFunction('accountId', [hookCopyInnerText]);

const updateStatus = async function (state) {
    document.getElementById('state').innerHTML = state;
    const eos = window.plugins.eos;
    if (eos.available && eos.initialized && (await eos.auth.isLoggedIn())) {
        getUsernameElement().innerText = await eos.auth.getUsername();
        getAccountIdElement().innerText = await eos.auth.getAccountId();
        const token = await eos.auth.getAuthToken();
        getTokenElement().innerText = token;
        const decodedToken = decodeToken(token);
        getJwtElement().innerText = JSON.stringify(decodedToken, undefined, 2);
    } else {
        getUsernameElement().innerText = '';
        getAccountIdElement().innerText = '';
        getJwtElement().innerText = '';
        getTokenElement().innerText = '';
    }
};

const testAuthService = function (createActionButton) {
    createActionButton(
        'Login Persistent',
        async function () {
            try {
                const eos = window.plugins.eos;
                if (!eos.initialized) {
                    console.warn('You must initialized the SDK first.');
                } else {
                    const success = await eos.auth.login(true);
                    console.log(`Logging in with persistent store: ${success}`);
                }
            } catch (err) {
                console.error(`Login Persistent error: ${err.message}`);
            }
        },
        'auth'
    );

    createActionButton(
        'Login Portal',
        async function () {
            try {
                const eos = window.plugins.eos;
                if (!eos.initialized) {
                    console.warn('You must initialized the SDK first.');
                } else {
                    const success = await eos.auth.login(false);
                    console.log(`Logging in with portal: ${success}`);
                }
            } catch (err) {
                console.error(`Login Portal error: ${err.message}`);
            }
        },
        'auth'
    );

    createActionButton(
        'Logout',
        async function () {
            try {
                const eos = window.plugins.eos;
                if (!eos.initialized) {
                    console.warn('You must initialized the SDK first.');
                } else {
                    const success = await eos.auth.logout();
                    console.log(`Logging out: ${success}`);
                }
            } catch (err) {
                console.error(`Login Persistent error: ${err.message}`);
            }
        },
        'auth'
    );

    createActionButton(
        'Refresh',
        async function () {
            try {
                await updateStatus('refresh');
            } catch (err) {
                console.error(`Login Persistent error: ${err.message}`);
            }
        },
        'auth'
    );
};

exports.setup = testAuthService;
// Special export for testSdkApi;
exports.updateStatus = updateStatus;
