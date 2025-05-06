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

#include <sys/types.h>
#include <sys/sysctl.h>
#include "TargetConditionals.h"
#import <os/log.h>

#import <Availability.h>

#import <Cordova/CDV.h>
#import "CordovaEOS.h"
#import "EOSWrapper.h"

@interface CordovaEOS () {}
-(void)sendLog: (NSString* _Nullable)message;
@end

@implementation CordovaEOS

CDVInvokedUrlCommand* _logCommand;
CDVInvokedUrlCommand* _loginCommand;
bool _isInitialized;
dispatch_source_t _source = nil;

- (void) pluginInitialize {
    _isInitialized = false;
    _logCommand = nil;
    _loginCommand = nil;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPause) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResume) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (dispatch_queue_t)getQueue {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
}

// Run Eos on a background queue, but always the same.
- (void)runEOS:(void (^)(void))block
{
    dispatch_async([self getQueue], block);
}

// SDK commands


- (void)getSDKVersion:(CDVInvokedUrlCommand*)command
{
    [self runEOS:^{
        NSDictionary*sdkVersion = @{@"sdkVersion": EOSWrapper.GetSDKVersion};
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:sdkVersion];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)startTickLoop {
    // Install the current timer on the main queue (which we assume is the same as the current queue).
    _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, [self getQueue]);
    dispatch_source_set_timer(_source, dispatch_walltime(NULL, 0), 100 * NSEC_PER_MSEC, 100 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(_source, ^ {
        if (_isInitialized) {
            [EOSWrapper Tick];
        }
    });
    dispatch_resume(_source);
}

- (void)installLoggingCallback {
    // Initialize the logging callback
    [EOSWrapper SetLoggingCallback: ^ (NSString* _Nullable message) {
        [self sendLog: message];
    }];
}

- (EOS_HPlatform)createPlatform: (nonnull NSString*) productId
                      sandboxId: (nonnull NSString*) sandboxId
                   deploymentId: (nonnull NSString*) deploymentId
                       clientId: (nullable NSString*) clientId
                   clientSecret: (nullable NSString*) clientSecret
{
    return [EOSWrapper CreatePlatform:productId
                                        sandboxId:sandboxId
                                        deploymentId:deploymentId
                                        clientId:clientId
                                        clientSecret:clientSecret
                                        isServer:NO
                                        flags:0];
}

- (void) sendLoginStatus: (NSString* _Nullable) status {
    if (_loginCommand != nil) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"status":status}];
        [result setKeepCallback:@YES];
        [self.commandDelegate sendPluginResult:result callbackId:_loginCommand.callbackId];
    }
}

- (void)installLoginStatusChangeCallback:(CDVInvokedUrlCommand*)command {
    _loginCommand = command;
    [EOSWrapper AddNotifyLoginStatusChanged: ^(bool isLoggedIn, bool wasLoggedIn){
        [self sendLoginStatus:isLoggedIn?@"loggedIn":@"loggedOut"];
    }];
}

- (void)uninstallLogingStatusChangeCallback {
    if (_loginCommand) {
        [EOSWrapper RemoveNotifyLoginStatusChanged];
        _loginCommand = nil;
    }
}

- (void)initializeSDK:(CDVInvokedUrlCommand*)command
{
    [self runEOS:^{
        os_log(OS_LOG_DEFAULT, "Initializing SDK");
        NSDictionary* config = [command argumentAtIndex: 0];
        NSString* ProductName = config[@"ProductName"];
        NSString* ProductVersion = config[@"ProductVersion"];
        NSString* ProductId = config[@"ProductId"];
        NSString* SandboxId = config[@"SandboxId"];
        NSString* DeploymentId = config[@"DeploymentId"];
        NSString* ClientId = config[@"ClientId"];
        NSString* ClientSecret = config[@"ClientSecret"];
        
        CDVPluginResult* result = nil;
        
        if (!_isInitialized) {
            EOS_EResult Result = [EOSWrapper InitializeSDK:ProductName version:ProductVersion];
            _isInitialized = Result == EOS_EResult::EOS_Success || Result == EOS_EResult::EOS_AlreadyConfigured;
            if (!_isInitialized) {
                NSString* error = [EOSWrapper ErrorAsString:Result];
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
                [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
                return;
            }
        }
        
        [self startTickLoop];
        
        [self installLoggingCallback];
        
        EOS_HPlatform HResult = [self createPlatform:ProductId
                                           sandboxId:SandboxId
                                        deploymentId:DeploymentId
                                            clientId:ClientId
                                        clientSecret:ClientSecret];
        
        if (HResult == nil) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error initializing platform"];
            [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
            return;
        }
        
        [self installLoginStatusChangeCallback:command];
        
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [result setKeepCallback:@YES];
        [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
    }];
}

- (void)onPause {
    [self runEOS:^{
        if (_isInitialized) {
            [self sendLog: @"Pausing EOS"];
            [EOSWrapper SignalUpdateToApplicationStatus:EOS_EApplicationStatus::EOS_AS_BackgroundSuspended];
        }
    }];
}

- (void)onResume {
    [self runEOS:^{
        if (_isInitialized) {
            [self sendLog: @"Resuming EOS"];
            [EOSWrapper SignalUpdateToApplicationStatus:EOS_EApplicationStatus::EOS_AS_Foreground];
        }
    }];
}

- (void)onAppTerminate {
    [self runEOS:^{
        if (_isInitialized) {
            [self sendLog: @"Terminate EOS"];
            [self uninstallLogingStatusChangeCallback];
            dispatch_source_cancel(_source);
            [EOSWrapper ShutdownSDK];
            _isInitialized = false;
        }
    }];
}

- (void)onConnect:(CDVInvokedUrlCommand*)command {
    [self runEOS:^{
        [EOSWrapper SignalUpdateToNetworkStatus: EOS_ENetworkStatus::EOS_NS_Online];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
    }];
}

- (void)onDisconnect:(CDVInvokedUrlCommand*)command {
    [self runEOS:^{
        
        [EOSWrapper SignalUpdateToNetworkStatus: EOS_ENetworkStatus::EOS_NS_Offline];
        
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
    }];
}

- (void)sendLog: (NSString* _Nullable)message {
    // TODO system log?
    if (message) {
        const char* cstr = [message cStringUsingEncoding:NSUTF8StringEncoding];
        os_log(OS_LOG_DEFAULT, "%s", cstr);
        if (_logCommand) {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"message":message}];
            [result setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:result callbackId: _logCommand.callbackId];
        }
    }
}

- (void)logs:(CDVInvokedUrlCommand*)command {
    if (_logCommand != nil) {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"message":@"End of logging"}];
        [self.commandDelegate sendPluginResult:result callbackId: _logCommand.callbackId];
    }
    // overwrite previous command
    _logCommand = command;
    [self sendLog: @"Logging handler installed"];
}

// Auth commands
- (void)isLoggedIn:(CDVInvokedUrlCommand*)command {
    [self runEOS:^{
        // Only Auth for now
        BOOL isLoggedIn = [EOSWrapper LoggedInViaAuthInterface] /* || [EOSWrapper LoggedInViaConnectInterface]*/;
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"isLoggedIn":@(isLoggedIn)}];
        [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
        
    }];
}

- (void)getUsername:(CDVInvokedUrlCommand*)command {
    [self runEOS:^{
        NSString* username = [EOSWrapper GetLoggedInDisplayName];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"username":username}];
        [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
    }];
}

- (void)getAccountId:(CDVInvokedUrlCommand*)command {
    [self runEOS:^{
        NSString* accountId = [EOSWrapper GetAccountId];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"accountId":accountId}];
        [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
    }];
}
- (void)getAuthToken:(CDVInvokedUrlCommand*)command {
    [self runEOS:^{
        NSString* token = [EOSWrapper GetAuthToken];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"authToken":token}];
        [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
    }];
}
- (void)loginPersistent:(CDVInvokedUrlCommand*)command  {
    [self runEOS:^{
        [self sendLoginStatus:@"inProgress"];
        [EOSWrapper LoginPersistentAuth:^(EOS_EResult Result){
            if (Result != EOS_EResult::EOS_Success) {
                NSString* error = [EOSWrapper ErrorAsString:Result];
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
                [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
            } else {
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
            }
        }];
    }];
}
- (void)loginPortal:(CDVInvokedUrlCommand*)command  {
    [self runEOS:^{
        [self sendLoginStatus:@"inProgress"];
        [EOSWrapper LoginWithAccountPortal:self completion:^(EOS_EResult Result){
            CDVPluginResult* result = nil;
            if (Result != EOS_EResult::EOS_Success) {
                NSString* error = [EOSWrapper ErrorAsString:Result];
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
            } else {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            }
            [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
        }];
    }];
}
- (void)logout:(CDVInvokedUrlCommand*)command  {
    [self runEOS:^{
        [EOSWrapper Logout:^(EOS_EResult Result){
            CDVPluginResult* result = nil;
            if (Result != EOS_EResult::EOS_Success) {
                NSString* error = [EOSWrapper ErrorAsString:Result];
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
            } else {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            }
            [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
        }];
    }];
}
// Ecom commands
- (void)queryEntitlements:(CDVInvokedUrlCommand*)command  {
    [self runEOS:^{
        [EOSWrapper QueryEntitlements:^(EOS_EResult Result, NSDictionary * _Nullable Value) {
            CDVPluginResult* result = nil;
            if (Result == EOS_EResult::EOS_Success) {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:Value];
            } else {
                NSString* error = [EOSWrapper ErrorAsString:Result];
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
            }
            [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
        }];
    }];
}
- (void)queryOffers:(CDVInvokedUrlCommand*)command  {
    [self runEOS:^{
        [EOSWrapper QueryOffers:^(EOS_EResult Result, NSDictionary * _Nullable Value) {
            CDVPluginResult* result = nil;
            if (Result == EOS_EResult::EOS_Success) {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:Value];
            } else {
                NSString* error = [EOSWrapper ErrorAsString:Result];
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
            }
            [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
        }];
    }];
}
- (void)checkout:(CDVInvokedUrlCommand*)command  {
    [self runEOS:^{
        NSArray* offers = [command argumentAtIndex:0];
        [EOSWrapper Checkout:offers completion:^(EOS_EResult Result, NSDictionary * _Nullable Value) {
            CDVPluginResult* result = nil;
            if (Result == EOS_EResult::EOS_Success) {
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:Value];
            } else {
                NSString* error = [EOSWrapper ErrorAsString:Result];
                result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
            }
            [self.commandDelegate sendPluginResult:result callbackId: command.callbackId];
        }];
    }];
}
// Require to comply on iOS 13+
- (nonnull ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(nonnull ASWebAuthenticationSession *)session API_AVAILABLE(ios(13.0)){
    return [[[UIApplication sharedApplication] windows] firstObject];
}
@end
