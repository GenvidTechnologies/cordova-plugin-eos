const { getElementByNameFunction, hookCopyInnerText, hookOnEvent } = require('./ui');

exports.innerHTML = `
    <details>
      <summary>Entitlements:</summary>
      <div>Selected Entitlement: <select id="entitlements" name="entitlements"></select></div>
      <details>
        <summary id="entitlementtitle"></summary>
        <pre><code id="entitlement"></code></pre>
        <button id="copyentitlement">Copy</button>
      </details>
    </details>
    <details>
      <summary>Offers:</summary>
      <div>Selected Offer: <select id="offers" name="offers"></select></div>
      <details>
        <summary id="offertitle"></summary>
        <pre><code id="offer"></code></pre>
        <button id="copyoffer">Copy</button>
      </details>
      <div>Selected Item: <select id="items" name="items"></select></div>
      <details>
        <summary id="itemtitle"></summary>
        <pre><code id="item"></code></pre>
        <button id="copyitem">Copy</button>
      </details>
    </details>
    <details>
      <summary>Transaction:</summary>
      <pre><code id="transaction"></code></pre>
      <button id="copytransaction">Copy</button>
    </details>
`;

// ************
// Entitlements
// ************

let entitlements = [];

const updateEntitlementDisplay = async function () {
    const entitlementsEl = getEntitlementsElement();
    const entitlementEl = getEntitlementElement();
    const entitlementTitleEl = document.getElementById('entitlementtitle');
    if (entitlementsEl.selectedIndex === -1) {
        console.log('Clearing entitlement');
        entitlementEl.innerText = '';
        entitlementTitleEl.innerText = '';
        clearItems();
    } else {
        const selectedId = entitlementsEl.value;
        console.log(`Updating entitlement ${selectedId}`);
        const entitlement = entitlements.find((v) => v.Id === selectedId);
        entitlementEl.innerText = JSON.stringify(entitlement, undefined, 2);
        entitlementTitleEl.innerText = entitlement.Name;
    }
};

const clearEntitlements = function () {
    const entitlementsEl = getEntitlementsElement();
    while (entitlementsEl.length > 0) {
        entitlementsEl.remove(entitlementsEl.length - 1);
    }
};

const updateEntitlements = async function () {
    const eos = window.plugins.eos;
    entitlements = await eos.ecom.queryEntitlements();
    clearEntitlements();
    const entitlementsEl = getEntitlementsElement();
    entitlements.forEach((o) => {
        entitlementsEl.add(new Option(o.Name, o.Id));
    });
    await updateEntitlementDisplay();
};

const getEntitlementsElement = getElementByNameFunction('entitlements', [hookOnEvent('change', updateEntitlementDisplay)]);
const getEntitlementElement = getElementByNameFunction('entitlement', [hookCopyInnerText]);

// ******
// Offers
// ******

let offers = [];

const getSelectedOffer = () => {
    const offersEl = getOffersElement();
    if (offersEl.selectedIndex === -1) {
        return undefined;
    }
    const offerId = offersEl.value;
    return offers.find((v) => v.Id === offerId);
};

const updateItemDisplay = function () {
    const itemsEl = getItemsElement();
    const itemEl = getItemElement();
    const itemTitleEl = document.getElementById('itemtitle');
    if (itemsEl.selectedIndex === -1) {
        console.log('Clearing item');
        itemEl.innerText = '';
        itemTitleEl.innerText = '';
    } else {
        const offer = getSelectedOffer();
        const selectedIdx = itemsEl.value;
        console.log(`Updating item ${selectedIdx}`);
        const item = offer.Items[selectedIdx];
        itemEl.innerText = JSON.stringify(item, undefined, 2);
        itemTitleEl.innerText = item.Title;
    }
};

const clearItems = function () {
    const itemsEl = getItemsElement();
    while (itemsEl.length > 0) {
        itemsEl.remove(itemsEl.length - 1);
    }
};

const updateItems = async function (items) {
    try {
        clearItems();
        const itemsEl = getItemsElement();
        items.forEach((i, idx) => {
            itemsEl.add(new Option(i.Title, idx));
        });
        updateItemDisplay();
    } catch (error) {
        console.error(`Error fetching items: ${error.message}`);
    }
};

const updateOfferDisplay = async function () {
    const offersEl = getOffersElement();
    const offerEl = getOfferElement();
    const offerTitleEl = document.getElementById('offertitle');
    if (offersEl.selectedIndex === -1) {
        console.log('Clearing offer');
        offerEl.innerText = '';
        offerTitleEl.innerText = '';
        clearItems();
    } else {
        const selectedId = offersEl.value;
        console.log(`Updating offer ${selectedId}`);
        const offer = offers.find((v) => v.Id === selectedId);
        const { Items, ...cleanOffer } = offer;
        offerEl.innerText = JSON.stringify(cleanOffer, undefined, 2);
        offerTitleEl.innerText = offer.Title;
        await updateItems(Items);
    }
};

const clearOffers = function () {
    const offersEl = getOffersElement();
    while (offersEl.length > 0) {
        offersEl.remove(offersEl.length - 1);
    }
};

const updateOffers = async function () {
    const eos = window.plugins.eos;
    offers = await eos.ecom.queryOffers();
    clearItems();
    clearOffers();
    const offersEl = getOffersElement();
    offers.forEach((o) => {
        offersEl.add(new Option(o.Title, o.Id));
    });
    await updateOfferDisplay();
};

const getOffersElement = getElementByNameFunction('offers', [hookOnEvent('change', updateOfferDisplay)]);
const getOfferElement = getElementByNameFunction('offer', [hookCopyInnerText]);
const getItemsElement = getElementByNameFunction('items', [hookOnEvent('change', updateItemDisplay)]);
const getItemElement = getElementByNameFunction('item', [hookCopyInnerText]);

// ********
// Checkout
// ********

const updateTransaction = (transaction) => {
    getTransactionElement().innerText = JSON.stringify(transaction, undefined, 2);
};

const getTransactionElement = getElementByNameFunction('transaction', [hookCopyInnerText]);

const testEcomService = function (createActionButton) {
    createActionButton(
        'Query Offers',
        async function () {
            try {
                const eos = window.plugins.eos;
                if (!eos.auth.isLoggedIn()) {
                    console.warn('User must be logged in.');
                    return;
                }
                await updateOffers();
            } catch (err) {
                console.error(`Query error: ${err.message} `);
            }
        },
        'ecom'
    );

    createActionButton(
        'Copy Offers',
        async function () {
            return navigator.clipboard.writeText(JSON.stringify(offers, undefined, 2));
        },
        'ecom'
    );

    createActionButton(
        'Query Entitlements',
        async function () {
            try {
                const eos = window.plugins.eos;
                if (!eos.auth.isLoggedIn()) {
                    console.warn('User must be logged in.');
                    return;
                }
                await updateEntitlements();
            } catch (err) {
                console.error(`Query error: ${err.message} `);
            }
        },
        'ecom'
    );

    createActionButton(
        'Copy Entitlements',
        async function () {
            return navigator.clipboard.writeText(JSON.stringify(entitlements, undefined, 2));
        },
        'ecom'
    );

    createActionButton(
        'Checkout',
        async function () {
            try {
                const eos = window.plugins.eos;
                if (!eos.auth.isLoggedIn()) {
                    console.warn('User must be logged in.');
                    return;
                }
                const offer = getSelectedOffer();
                if (!offer) {
                    console.warn('You need to select an offer.');
                    return;
                }
                const transaction = await eos.ecom.checkout([offer.Id]);
                updateTransaction(transaction);
            } catch (err) {
                console.error(`Checkout error: ${err.message} `);
            }
        },
        'ecom'
    );
};

exports.setup = testEcomService;
