// Copyright Epic Games, Inc. All Rights Reserved.

#ifndef EOSWrapper_h
#define EOSWrapper_h

#import <Foundation/Foundation.h>

#include "EOSSDK/eos_sdk.h"
#include "EOSSDK/eos_common.h"

/** Callback types for returning results to the application */
typedef void (^LoginCompletion)(EOS_EResult Result);
typedef void (^LogoutCompletion)(EOS_EResult Result);
typedef void (^NotifyLoginStatusChangedCompletion)(bool LoggedIn, bool PrevLoggedIn);
typedef void (^SDKLog)(NSString* _Nullable Message);
typedef void (^EntitlementsCompletion)(EOS_EResult Result, NSDictionary* _Nullable Value);
typedef void (^OffersCompletion)(EOS_EResult Result, NSDictionary* _Nullable Value);
typedef void (^CheckoutCompletion)(EOS_EResult Result, NSDictionary* _Nullable Value);

@interface EOSWrapper : NSObject

+ (EOS_EResult) InitializeSDK: (nonnull NSString*) ProductName version:(nonnull NSString*) version;
+ (nullable EOS_HPlatform) CreatePlatform: (nonnull NSString*) productId
								sandboxId: (nonnull NSString*) sandboxId
							 deploymentId: (nonnull NSString*) deploymentId
								 clientId: (nullable NSString*) clientId
							 clientSecret: (nullable NSString*) clientSecret
								 isServer: (BOOL) isServer
									flags: (uint64_t) flags;
+ (void) Tick;
+ (void) ReleasePlatform: (nonnull EOS_HPlatform) platform;
+ (EOS_EResult) ShutdownSDK;
+ (void) SetLoggingCallback: (nonnull SDKLog) log;
+ (nonnull NSString*) GetSDKVersion;
+ (nonnull NSString*) ErrorAsString: (EOS_EResult)error;

// MARK: - Login and User State

+ (void) LoginPersistentAuth: (nonnull LoginCompletion) completion;
+ (void) LoginWithAccountPortal: (nullable id) presentationContextProviding completion: (nonnull LoginCompletion) completion;
+ (void) LoginWithAppleIDToken: (nonnull NSString*) token displayName: (nonnull NSString*) displayName completion: (nonnull LoginCompletion) completion;
+ (void) Logout: (nonnull LogoutCompletion) completion;

+ (BOOL) LoggedInViaAuthInterface;
+ (BOOL) LoggedInViaConnectInterface;

+ (nonnull NSString*) GetLoggedInDisplayName;
+ (nonnull NSString*) GetAccountId;
+ (nonnull NSString*) GetAuthToken;

+ (void) AddNotifyLoginStatusChanged: (nonnull NotifyLoginStatusChangedCompletion) completion;
+ (void) RemoveNotifyLoginStatusChanged;

// MARK: - Network Status
+ (EOS_EResult) SignalUpdateToNetworkStatus: (EOS_ENetworkStatus) status;

// MARK: - Application Status
+ (EOS_EResult) SignalUpdateToApplicationStatus: (EOS_EApplicationStatus) status;

// MARK: - ECom API

+ (void) QueryEntitlements: (nonnull EntitlementsCompletion) completion;
+ (void) QueryOffers: (nonnull OffersCompletion) completion;
+ (void) Checkout: (nonnull NSArray*)offers completion: (nonnull CheckoutCompletion) completion;

@end

#endif /* EOSWrapper_h */
