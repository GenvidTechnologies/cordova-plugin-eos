const testSdkApi = require('./testSdkApi');
const testAuthService = require('./testAuthService');
const testEcomService = require('./testEcomService');

const manualTests = function (contentEl, createActionButton) {
    const orderedTabs = ['sdk', 'auth', 'ecom'];
    const modules = {
        sdk: testSdkApi,
        auth: testAuthService,
        ecom: testEcomService
    };
    const tabsHTML = orderedTabs.map(tab => {
        return `
<details>
  <summary>${tab.toUpperCase()}</summary>
  <div style="border: solid; padding: 5px" id="${tab}">${modules[tab].innerHTML}</div>
</details>`;
    }).join('\n');
    contentEl.innerHTML = `
    <h3>EOS Tests</h3>
    <div id="tests">
        ${tabsHTML}
    </div > `;
    for (const tab of orderedTabs) {
        modules[tab].setup(createActionButton);
    }
};

exports.manualTests = manualTests;
