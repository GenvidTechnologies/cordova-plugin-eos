const getElementByNameFunction = function (name, hooks) {
    let element;
    return function () {
        if (element === undefined) {
            element = document.getElementById(name);
            if (element) {
                if (hooks) {
                    for (const hook of hooks) {
                        hook(name, element);
                    }
                }
            }
        }
        return element;
    };
};

const hookCopyInnerText = function (name, element) {
    try {
        document.getElementById('copy' + name).addEventListener('click', () => {
            navigator.clipboard.writeText(element.innerText);
        });
    } catch (error) {
        console.error(`Error installing click listener on copy${name}: ${error.message}`);
    }
};

const hookOnEvent = function (event, callback) {
    return function (name, element) {
        try {
            element.addEventListener(event, callback);
        } catch (error) {
            console.error(`Error installing ${event} listener on ${name}: ${error.message}`);
        }
    };
};

exports.getElementByNameFunction = getElementByNameFunction;
exports.hookCopyInnerText = hookCopyInnerText;
exports.hookOnEvent = hookOnEvent;
