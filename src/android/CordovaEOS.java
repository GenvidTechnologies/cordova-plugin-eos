/*
       Licensed to the Apache Software Foundation (ASF) under one
       or more contributor license agreements.  See the NOTICE file
       distributed with this work for additional information
       regarding copyright ownership.  The ASF licenses this file
       to you under the Apache License, Version 2.0 (the
       "License"); you may not use this file except in compliance
       with the License.  You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing,
       software distributed under the License is distributed on an
       "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
       KIND, either express or implied.  See the License for the
       specific language governing permissions and limitations
       under the License.
*/
package com.genvidtech.cordova.eos;

import org.apache.cordova.CordovaWebView;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.util.Log;

import java.lang.Runnable;

import com.epicgames.mobile.eossdk.EOSSDK;

public class CordovaEOS extends CordovaPlugin {

    private static final String LogTag = "CordovaEOS";
    public static boolean librariesLoaded = false;

    // Tick handlers
    private Handler tickHandler = null;
    private Runnable tickRunnable = null;

    // Login callback
    private CallbackContext loginStateCallbackContext = null;
    private CallbackContext loggingCallbackContext = null;

    /**
     * Constructor.
     */
    public CordovaEOS() {}

    public boolean InitializeEOS(JSONObject config) throws JSONException {
        // Check all the arguments first.
        String ProductName = config.getString("ProductName");
        String ProductVersion = config.getString("ProductVersion");
        String ProductId = config.getString("ProductId");
        String SandboxId = config.getString("SandboxId");
        String DeploymentId = config.getString("DeploymentId");
        String ClientId = config.getString("ClientId");
        String ClientSecret = config.getString("ClientSecret");

        loadLibraries();

        PassCordovaEOSInstance();

        Activity activity = this.cordova.getActivity();
        EOSSDK.init(activity);

        if (!InitializeSDK(ProductName, ProductVersion, activity.getFilesDir().getAbsolutePath() + "/"))
        {
            return false;
        }
        if (!CreatePlatform(
            ProductId,
            SandboxId,
            DeploymentId,
            ClientId,
            ClientSecret,
            false /* isServer */,
            0 /* flags */
            )) {
                return false;
            }
        return true;
    }

    static private void loadLibraries() {
        if (!librariesLoaded) {
            System.loadLibrary("EOSSDK");
            System.loadLibrary("CordovaEOS");
            librariesLoaded = true;
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        stopTickLoop();
    }

    @Override
    public void onPause(boolean multitasking) {
        super.onPause(multitasking);
        Suspend();
    }

    @Override
    public void onResume(boolean multitasking) {
        super.onResume(multitasking);
        Resume();
    }

    // All calls to EOS need to be made in the UI thread.
    // 
    private void runOnUiThread(Runnable r) {
        cordova.getActivity().runOnUiThread(r);
    }

    private void sendLoginStatus(String status) {
        if (loginStateCallbackContext != null) {
            JSONObject resp = new JSONObject();
            try {
                resp.put("status", status);
            } catch(JSONException err) {
                Log.e(LogTag, "JSON Exception on sendLoginStatus: " + err.getMessage());
            }
            PluginResult result = new PluginResult(PluginResult.Status.OK, resp);
            result.setKeepCallback(true);
            loginStateCallbackContext.sendPluginResult(result);
        }
    }

    private boolean handleGetSDKVersion(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            try {
                JSONObject resp = new JSONObject();
                resp.put("sdkVersion", GetVersion());
                callbackContext.success(resp);
            } catch(JSONException err) {
                callbackContext.error("Exception writing response: " + err.getMessage());
            }
        });
        return true;
    }

    private boolean handleInitializeSDK(CallbackContext callbackContext, JSONArray args) {
        runOnUiThread(() -> {
            loginStateCallbackContext = callbackContext;
            try {
                if (InitializeEOS(args.getJSONObject(0))) {
                    startTickLoop();
                    sendLoginStatus(IsLoggedIn() ? "loggedIn" : "loggedOut");
                } else {
                    loginStateCallbackContext = null;
                    callbackContext.error("Fail to initialize EOS SDK");
                }
            } catch(JSONException err) {
                loginStateCallbackContext = null;
                callbackContext.error("Invalid argument for initializeSDK: " + err.getMessage());
            }
        });
        return true;
    }


    private boolean handleShutdownSDK(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            Shutdown();
            stopTickLoop();
            if (loginStateCallbackContext != null) {
                loginStateCallbackContext.success();
                loginStateCallbackContext = null;
            }
            callbackContext.success();
        });

        return true;
    }

    private boolean handleIsLoggedIn(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            try {
                JSONObject resp = new JSONObject();
                resp.put("isLoggedIn", IsLoggedIn());
                callbackContext.success(resp);
            } catch(JSONException err) {
                callbackContext.error("Exception writing response: " + err.getMessage());
            }
        });
        return true;
    }

    private boolean handleGetUsername(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            try {
                JSONObject resp = new JSONObject();
                resp.put("username", GetUsername());
                callbackContext.success(resp);
            } catch(JSONException err) {
                callbackContext.error("Exception writing response: " + err.getMessage());
            }
        });
        return true;
    }

    private boolean handleGetAccountId(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            if (!IsLoggedIn()) {
                callbackContext.error("");
            } else {
                try {
                    JSONObject resp = new JSONObject();
                    resp.put("accountId", GetAccountId());
                    callbackContext.success(resp);
                } catch(JSONException err) {
                    callbackContext.error("Exception writing response: " + err.getMessage());
                }
            }
        });
        return true;
    }

    private boolean handleGetAuthToken(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            if (!IsLoggedIn()) {
                callbackContext.error("");
            } else {
                try {
                    JSONObject resp = new JSONObject();
                    resp.put("authToken", GetAuthToken());
                    callbackContext.success(resp);
                } catch(JSONException err) {
                    callbackContext.error("Exception writing response: " + err.getMessage());
                }
            }
        });
        return true;
    }

    private boolean handleLogin(CallbackContext callbackContext, boolean persistent) {
        runOnUiThread(() -> {
            if (IsLoggedIn()) {
                callbackContext.error("User already logged in.");
            } else {
                if (persistent) {
                    LoginPersistent(callbackContext);
                } else {
                    LoginWithPortal(callbackContext);
                }
            }
        });
        return true;
    }

    private boolean handleLogout(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            Logout(callbackContext);
        });
        return true;
    }

    private boolean handleOnConnect(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            NetworkChanged(true);
            callbackContext.success();
        });
        return true;
    }

    private boolean handleOnDisconnect(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            NetworkChanged(false);
            callbackContext.success();
        });
        return true;
    }

    /**
     * ECom section
     */

    private boolean handleQueryEntitlements(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            if (!IsLoggedIn()) {
                callbackContext.error("User not logged in");
                return;
            }
            QueryEntitlements(callbackContext);
        });
        return true;
    }

    private boolean handleQueryOffers(CallbackContext callbackContext) {
        runOnUiThread(() -> {
            if (!IsLoggedIn()) {
                callbackContext.error("User not logged in");
                return;
            }
            QueryOffers(callbackContext);
        });
        return true;
    }

    private boolean handleCheckout(CallbackContext callbackContext, JSONArray args) throws JSONException {
        JSONArray jsonOfferIds = args.getJSONArray(0);
        int offersCount = jsonOfferIds.length();
        if (offersCount == 0) {
            callbackContext.error("No offers to checkout");
            return true;
        }
        String offerIds[] = new String[offersCount];
        for(int i = 0; i < offersCount; ++i) {
            offerIds[i] = jsonOfferIds.getString(i);
        }
        runOnUiThread(() -> {
            if (!IsLoggedIn()) {
                callbackContext.error("User not logged in");
                return;
            }
            Checkout(offerIds, callbackContext);
        });
        return true;
    }

    private boolean handleLogs(CallbackContext callbackContext) {
        if (loggingCallbackContext != null) {
            try {
                JSONObject resp = new JSONObject();
                resp.put("message", "End of logging");
                loggingCallbackContext.success(resp);
            } catch (JSONException err) {
                Log.e(LogTag, "Error ending logging: " + err.getMessage());
            }
        }
        loggingCallbackContext = callbackContext;
        LogText("Logging handler installed");
        return true;
    }

    /**
     * Executes the request and returns PluginResult.
     *
     * @param action            The action to execute.
     * @param args              JSONArray of arguments for the plugin.
     * @param callbackContext   The callback id used when calling back into JavaScript.
     * @return                  True if the action was valid, false if not.
     */
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        switch (action) {
            // sdk interface
            case "getSDKVersion":
                return handleGetSDKVersion(callbackContext);
            case "initializeSDK":
                return handleInitializeSDK(callbackContext, args);
            case "shutdownSDK":
                return handleShutdownSDK(callbackContext);
            case "onConnect":
                return handleOnConnect(callbackContext);
            case "onDisconnect":
                return handleOnDisconnect(callbackContext);
            // auth interface
            case "isLoggedIn":
                return handleIsLoggedIn(callbackContext);
            case "getUsername":
                return handleGetUsername(callbackContext);
            case "getAccountId":
                return handleGetAccountId(callbackContext);
            case "getAuthToken":
                return handleGetAuthToken(callbackContext);
            case "loginPersistent":
                return handleLogin(callbackContext, true);
            case "loginPortal":
                return handleLogin(callbackContext, false);
            case "logout":
                return handleLogout(callbackContext);
            // ECom interface
            case "queryEntitlements":
                return handleQueryEntitlements(callbackContext);
            case "queryOffers":
                return handleQueryOffers(callbackContext);
            case "checkout":
                return handleCheckout(callbackContext, args);
            case "logs":
                return handleLogs(callbackContext);
            default:
                return false;
        }
    }

    //--------------------------------------------------------------------------
    // LOCAL METHODS
    //--------------------------------------------------------------------------

    /**
     * This will maintain calling itself every 10th of a second after the initial trigger
     */
    private void startTickLoop() {
        tickHandler = new Handler(Looper.getMainLooper());
        tickRunnable = new Runnable() {
            public void run() {
                Tick();
                tickHandler.postDelayed(this, 100);
            }
        };
        tickHandler.post(tickRunnable);
    }

    private void stopTickLoop() {
        if (tickHandler != null) {
            tickHandler.removeCallbacks(tickRunnable);
        }
    }

    // Callback from natives:

    /**
     * Helper function to view text on screen
     * TODO: Add log level
     * TODO: Forward logs to console
     */
    public void LogText(String text) {
        Log.v(LogTag, text);
        if (loggingCallbackContext != null) {
            JSONObject resp = new JSONObject();
            try {
                resp.put("message", text);
            } catch(JSONException err) {
                Log.e(LogTag, "JSON Exception on LogText: " + err.getMessage());
            }
            PluginResult result = new PluginResult(PluginResult.Status.OK, resp);
            result.setKeepCallback(true);
            loggingCallbackContext.sendPluginResult(result);
        }
    }

    /**
     * Helper function to hide/show Login/Logout button
     */
    public void LoginStateChanged(boolean loggedIn) {
        Log.v(LogTag, loggedIn ? "Logged In" : "Logged Out");
        Log.v(LogTag, "User: " + GetUsername());
        sendLoginStatus(loggedIn ? "loggedIn" : "loggedOut");
    }

    public void LoginInProgress() {
        Log.v(LogTag, "Login In Progress");
        sendLoginStatus("inProgress");
    }

    public void LoginResult(boolean success, Object context) {
        CallbackContext callbackContext = (CallbackContext)context;
        Log.v(LogTag, "Logging in/out Result: " + (success ? "success" : "error"));
        try {
            JSONObject resp = new JSONObject();
            resp.put("result", success);
            callbackContext.success(resp);
        } catch(JSONException error) {
            callbackContext.error("Error serializing response: " + error.getMessage());
        }
    }

    public void OnQueryEntitlementsResult(boolean success, String value, Object context) {
        CallbackContext callbackContext = (CallbackContext) context;
        if (!success) {
            callbackContext.error(value);
            return;
        }
        try {
            JSONObject resp = (JSONObject) new JSONTokener(value).nextValue();
            callbackContext.success(resp);
        } catch(JSONException err) {
            callbackContext.error("Exception writing response: " + err.getMessage());
        }
    }

    public void OnQueryOffersResult(boolean success, String value, Object context) {
        CallbackContext callbackContext = (CallbackContext) context;
        if (!success) {
            callbackContext.error(value);
            return;
        }
        try {
            JSONObject resp = (JSONObject) new JSONTokener(value).nextValue();
            callbackContext.success(resp);
        } catch(JSONException err) {
            callbackContext.error("Exception writing response: " + err.getMessage());
        }
    }

    public void OnCheckoutResult(boolean success, String value, Object context) {
        CallbackContext callbackContext = (CallbackContext) context;
        if (!success) {
            callbackContext.error(value);
            return;
        }
        try {
            JSONObject resp = (JSONObject) new JSONTokener(value).nextValue();
            callbackContext.success(resp);
        } catch(JSONException err) {
            callbackContext.error("Exception writing response: " + err.getMessage());
        }
    }

    //--------------------------------------------------------------------------
    // NATIVE METHODS
    //--------------------------------------------------------------------------

    /**
     * Native functions callable from java
     */
    private native boolean InitializeSDK(String ProductName, String ProductVersion, String Path);

    private native void ShutdownSDK();

    private native String GetVersion();

    private native boolean CreatePlatform(String ProductID, String SandboxID, String DeploymentId, String ClientId, String ClientSecret, boolean IsServer, int Flags);

    private native void Logout(Object context);

    private native void Tick();

    private native void Suspend();

    private native void Resume();

    private native void NetworkChanged(boolean connected);

    private native void LoginPersistent(Object context);

    private native void LoginWithPortal(Object context);

    private native boolean IsLoggedIn();

    private native String GetUsername();

    private native String GetAccountId();

    private native String GetAuthToken();

    private native void PassCordovaEOSInstance();

    // ECom native methods

    private native void QueryEntitlements(Object context);

    private native void QueryOffers(Object context);

    private native void Checkout(String offerIds[], Object context);

}
