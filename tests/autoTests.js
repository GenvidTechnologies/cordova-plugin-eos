exports.autoTests = function () {
    describe('EOS Interface (window.plugins.eos)', function () {
        it('should exist', function () {
            expect(window.plugins.eos).toBeDefined();
        });

        it('should be available', function () {
            expect(window.plugins.eos.available).toBe(true);
        });

        it('should be able to initialize', async function (done) {
            try {
                const response = await fetch('../eos_config.json');
                expect(response.ok).toBe(true);
                const SDKConfig = await response.json();
                expect(window.plugins.eos.initializeSDK).toBeDefined();
                await window.plugins.eos.initializeSDK(SDKConfig, () => { });
                expect(window.plugins.eos.initialized).toBe(true);
                expect(window.plugins.eos.sdkVersion).toBeDefined();
                expect(typeof window.plugins.eos.sdkVersion).toBe('string');
                done();
            } catch (err) {
                expect('there should not be an error but there is:').toBe(err.message);
                done();
            }
        });

        it('should be able to tell if it is logged in or not', async function (done) {
            try {
                expect(await window.plugins.eos.auth).toBeDefined();
                expect(await window.plugins.eos.auth.isLoggedIn).toBeDefined();
                const isLoggedIn = await window.plugins.eos.auth.isLoggedIn();
                expect(typeof isLoggedIn).toBe('boolean');
                done();
            } catch (err) {
                expect('there should not be an error but there is:').toBe(err.message);
                done();
            }
        });

        it('should be able to get the current username', async function (done) {
            try {
                expect(await window.plugins.eos.auth).toBeDefined();
                expect(await window.plugins.eos.auth.getUsername).toBeDefined();
                const username = await window.plugins.eos.auth.getUsername();
                expect(typeof username).toBe('string');
                done();
            } catch (err) {
                expect('there should not be an error but there is:').toBe(err.message);
                done();
            }
        });

        it('should have ecom interface', async function (done) {
            try {
                expect(await window.plugins.eos.ecom).toBeDefined();
                expect(await window.plugins.eos.ecom.queryOffers).toBeDefined();
                expect(await window.plugins.eos.ecom.checkout).toBeDefined();
                done();
            } catch (err) {
                expect('there should not be an error but there is:').toBe(err.message);
                done();
            }
        });
    });
};
