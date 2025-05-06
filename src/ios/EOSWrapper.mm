// Copyright Epic Games, Inc. All Rights Reserved.
// Copyright Genvid Technologies, LLC. All Rights Reserved.

#import <Foundation/Foundation.h>
#import <os/log.h>

#import "EOSWrapper.h"
#import "ReservedPlatformOptions.h"

#import "EOSSDK/eos_sdk.h"
#import "EOSSDK/eos_auth.h"
#import "EOSSDK/eos_connect.h"
#import "EOSSDK/eos_logging.h"
#import "EOSSDK/eos_init.h"
#import "EOSSDK/eos_userinfo.h"
#import "EOSSDK/eos_ios.h"
#import "EOSSDK/eos_version.h"
#import "EOSSDK/eos_ecom.h"

#include <set>

/** EOSWrapper provides an Objective-C interface to the underlying EOS SDK's C++ based interface
 *  Many of these functions are asynchronous in nature, so we need to be prepared to handle results appropriately
 *  Core EOS SDK functions used in this sample are wrapped here and we define callbacks where relevant, so that we can capture the result of our requests
 *  We also handle the tracking and execution of application supplied callbacks, which will return results back to the initiator */

std::set<EOS_HPlatform> GPlatforms;

@interface EOSWrapper()
+ (void) DeletePersistentAuth: (nonnull void (^)(EOS_EResult Result)) completion;
@end


@implementation EOSWrapper

// EAS
static EOS_EpicAccountId LocalUserId = nullptr;
static EOS_UserInfo *LocalUserInfo = nullptr;

// SIWA
static EOS_ProductUserId ProductLocalUserId = nullptr;

// Application callback support tracking
static LoginCompletion LoginCompletionCB = nil;
static LogoutCompletion LogoutCompletionCB = nil;
static NotifyLoginStatusChangedCompletion NotifyLoginStatusChangedCompletionCB = nil;
static SDKLog SDKLogCB = nil;
static EntitlementsCompletion EntitlementsCompletionCB = nil;
static OffersCompletion OffersCompletionCB = nil;
static CheckoutCompletion CheckoutCompletionCB = nil;

static void (^DeletePersistentAuthCompletionCB)(EOS_EResult Result) = nil;

static EOS_NotificationId NotifyLoginStatusChanged = 0;

+ (nonnull NSString*) ErrorAsString: (EOS_EResult) error
{
    const char* errorAsString = EOS_EResult_ToString(error);
	return [NSString stringWithUTF8String:errorAsString];
}

/** Initialize the EOS SDK for use before we call any other functions, normally during application launching
 *  We supply the applications product name and current version number
 *  NOTE: initializeSDK and shutdownSDK must be called on the main thread */
+ (EOS_EResult) InitializeSDK: (NSString*) ProductName version:(NSString*) version
{
	EOS_InitializeOptions SDKOptions = {0};
	SDKOptions.ApiVersion = EOS_INITIALIZE_API_LATEST;
	SDKOptions.ProductName = ProductName.UTF8String;
	SDKOptions.ProductVersion = version.UTF8String;

	return EOS_Initialize(&SDKOptions);
}

/** Initialize the platform interface using the settings we have obtained from the Developer Portal
 *  This is our hub interface for gaining access to other systems */
+ (nullable EOS_HPlatform) CreatePlatform: (nonnull NSString*) productId
								sandboxId: (nonnull NSString*) sandboxId
							 deploymentId: (nonnull NSString*) deploymentId
								 clientId: (nullable NSString*) clientId
							 clientSecret: (nullable NSString*) clientSecret
								 isServer: (BOOL) isServer
									flags: (uint64_t) flags
{
	EOS_Platform_Options PlatformOptions = {0};
	PlatformOptions.ApiVersion = EOS_PLATFORM_OPTIONS_API_LATEST;
	PlatformOptions.ProductId = productId.UTF8String;
	PlatformOptions.SandboxId = sandboxId.UTF8String;
	PlatformOptions.DeploymentId = deploymentId.UTF8String;
	PlatformOptions.bIsServer = isServer ? EOS_TRUE : EOS_FALSE;
	PlatformOptions.ClientCredentials.ClientId = clientId ? clientId.UTF8String : NULL;
	PlatformOptions.ClientCredentials.ClientSecret = clientSecret ? clientSecret.UTF8String : NULL;
	PlatformOptions.Flags = flags;
    [ReservedPlatformOptions SetReservedPlatformOptions:PlatformOptions];
	EOS_HPlatform Result = EOS_Platform_Create(&PlatformOptions);
	if (Result != NULL)
	{
		GPlatforms.insert(Result);
	}
	return Result;
}

/** Tick all active platforms so that they can update and processes any in-flight/incoming HTTP requests or services */
+ (void) Tick
{
	for (EOS_HPlatform platform : GPlatforms)
	{
		EOS_Platform_Tick(platform);
	}
}

/** Release a platform we previously created
 *  NOTE: ShutdownSDK will release platforms for us during application termination and is the preferred way to handle this
 *  Only use this if you need to release a platform for reasons other than application shutdown */
+ (void) ReleasePlatform: (nonnull EOS_HPlatform) platform
{
	SDKLogCB = nil;
	EOS_Platform_Release(platform);
	GPlatforms.erase(platform);
}

/** Shutdown the EOS SDK, normally during application termination
 *  This is also the safest way to release any created platforms we are tracking
 *  NOTE: initializeSDK and shutdownSDK must be called on the main thread */
+ (EOS_EResult) ShutdownSDK
{
	// Release all created platforms
	for (EOS_HPlatform platform : GPlatforms)
	{
		EOS_Platform_Release(platform);
	}
	GPlatforms.clear();

	// Release any data returned to us from GetLoggedInDisplayName
	if (LocalUserInfo != nullptr) {
		EOS_UserInfo_Release(LocalUserInfo);
		LocalUserInfo = nullptr;
	}

	return EOS_Shutdown();
}

+ (nonnull NSString*) GetSDKVersion {
  return [NSString stringWithUTF8String: EOS_GetVersion()];
}

+ (void) SetLoggingCallback: (nonnull SDKLog) log {
	SDKLogCB = log;
	EOS_Logging_SetLogLevel(EOS_ELogCategory::EOS_LC_ALL_CATEGORIES, EOS_ELogLevel::EOS_LOG_Verbose);
	EOS_EResult callbackResult = EOS_Logging_SetCallback(LoggingCb);
	assert(callbackResult == EOS_EResult::EOS_Success);
}

void EOS_CALL LoggingCb(const EOS_LogMessage* InMessage)
{
	if (SDKLogCB != nullptr) {
		if (InMessage->Message != nullptr) {
			NSString *Message = [NSString stringWithUTF8String:InMessage->Message];
			SDKLogCB(Message);
		}
	}
}

// MARK: - Login and User State

/** Attempt a login to the EOS Auth Interface with any previously stored secure credentials (as a result of a previous session calling LoginWithAccountPortal successfully)
 *  If no credential exist then the result EOS_NotFound will be returned to indicate the we still need to login for the first time
 *  If credentials do exist they will be maintained across sessions until we call logout
 *  This should be called after createPlatform and before allowing the user any manual login options */
+ (void) LoginPersistentAuth: (nonnull LoginCompletion) completion
{
	os_log(OS_LOG_DEFAULT, "LoginPersistentAuth:");

	EOS_HPlatform platform = *GPlatforms.begin();
	EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(platform);

	EOS_Auth_Credentials Credentials;
	Credentials.ApiVersion = EOS_AUTH_CREDENTIALS_API_LATEST;
	Credentials.Type = EOS_ELoginCredentialType::EOS_LCT_PersistentAuth;
	Credentials.Id = nullptr;
	Credentials.Token = nullptr;
	Credentials.SystemAuthCredentialsOptions = nullptr;
	Credentials.ExternalType = EOS_EExternalCredentialType::EOS_ECT_EPIC_ID_TOKEN;

	EOS_Auth_LoginOptions LoginOptions = {};
	LoginOptions.ApiVersion = EOS_AUTH_LOGIN_API_LATEST;
	LoginOptions.Credentials = &Credentials;

	LoginCompletionCB = completion;
	EOS_Auth_Login(AuthHandle, &LoginOptions, nullptr, LoginPersistentAuthCb);
}

/** Callback to handle result of attempting a login with stored secure credentials
 *  Will return the result to the applications supplied callback */
void EOS_CALL LoginPersistentAuthCb(const EOS_Auth_LoginCallbackInfo* Info)
{
	assert(Info != NULL);
	if (!EOS_EResult_IsOperationComplete(Info->ResultCode))
	{
		return;
	}

	os_log(OS_LOG_DEFAULT, "LoginPersistentAuth: Result=%s", EOS_EResult_ToString(Info->ResultCode));
	bool bSuccessful = Info->ResultCode == EOS_EResult::EOS_Success;

	if (bSuccessful) {
		os_log(OS_LOG_DEFAULT, "LoginPersistentAuth: Login Successful");
		LocalUserId = Info->LocalUserId;
	}
	else {
		// Check the specific error if we fail to complete a persistent login attempt, as we may need to flush any stored secure credentials
		switch (Info->ResultCode) {
			case EOS_EResult::EOS_Canceled:
			case EOS_EResult::EOS_AlreadyPending:
			case EOS_EResult::EOS_TooManyRequests:
			case EOS_EResult::EOS_TimedOut:
			case EOS_EResult::EOS_ServiceFailure:
			case EOS_EResult::EOS_NotFound:
				os_log(OS_LOG_DEFAULT, "LoginPersistentAuth: Login Failed");
				break;
			default:
				os_log(OS_LOG_DEFAULT, "LoginPersistentAuth: Delete persistent auth");
				[EOSWrapper DeletePersistentAuth: ^(EOS_EResult Result)
				{
					LoginCompletionCB(Result);
				}];
				return;
		}
	}

	LoginCompletionCB(Info->ResultCode);
}

/** Attempt a login to the EOS Auth Interface using the web account portal */
+ (void) LoginWithAccountPortal: (nullable id) presentationContextProviding completion: (nonnull LoginCompletion) completion
{
	os_log(OS_LOG_DEFAULT, "LoginWithAccountPortal:");

	EOS_HPlatform platform = *GPlatforms.begin();
	EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(platform);

	// For iOS 13+ we need to pass the applications protocol implementation for ASWebAuthenticationPresentationContextProviding
	// We bridge this to the C++ API using CFBridgingRetain, the EOS SDK will always release the bridged value as part of the contract
	// NOTE: The SDK will consume this data before the scope is lost
	EOS_IOS_Auth_CredentialsOptions CredentialsOptions = {};
	CredentialsOptions.ApiVersion = EOS_IOS_AUTH_CREDENTIALSOPTIONS_API_LATEST;
	if (@available(iOS 13.0, *))
	{
		CredentialsOptions.PresentationContextProviding = (void*)CFBridgingRetain(presentationContextProviding);		// SDK will release when consumed
	}

	EOS_Auth_Credentials Credentials = {};
	Credentials.ApiVersion = EOS_AUTH_CREDENTIALS_API_LATEST;
	Credentials.Type = EOS_ELoginCredentialType::EOS_LCT_AccountPortal;
	Credentials.Id = nullptr;
	Credentials.Token = nullptr;
	Credentials.SystemAuthCredentialsOptions = (void*)&CredentialsOptions;

	EOS_Auth_LoginOptions LoginOptions = {};
	LoginOptions.ApiVersion = EOS_AUTH_LOGIN_API_LATEST;
	LoginOptions.ScopeFlags =(EOS_EAuthScopeFlags)(
		EOS_EAuthScopeFlags::EOS_AS_BasicProfile |
		EOS_EAuthScopeFlags::EOS_AS_Country);
	LoginOptions.Credentials = &Credentials;

	LoginCompletionCB = completion;
	EOS_Auth_Login(AuthHandle, &LoginOptions, nullptr, AuthLoginCb);
}

/** Callback to handle result of attempting a login using the web account portal
 *  Will return the result to the applications supplied callback */
void EOS_CALL AuthLoginCb(const EOS_Auth_LoginCallbackInfo* Info)
{
	assert(Info != NULL);
	if (!EOS_EResult_IsOperationComplete(Info->ResultCode))
	{
		return;
	}

	os_log(OS_LOG_DEFAULT, "LoginWithAccountPortal: Result=%s", EOS_EResult_ToString(Info->ResultCode));
	bool bSuccessful = Info->ResultCode == EOS_EResult::EOS_Success;

	if (bSuccessful) {
		LocalUserId = Info->LocalUserId;
	}

	LoginCompletionCB(Info->ResultCode);
}

/** Attempt a login to the EOS Connect Interface using an Apple token received from a Sign in with Apple request
 *  NOTE: "displayName" is how this user will appear in EOS services, this should be sourced from the user before making this call */
+ (void) LoginWithAppleIDToken: (nonnull NSString*) token displayName: (nonnull NSString*) displayName completion: (nonnull LoginCompletion) completion
{
	os_log(OS_LOG_DEFAULT, "LoginWithAppleIDToken:");

	const char *cstrToken = [token cStringUsingEncoding:NSUTF8StringEncoding];
	const char *cstrDisplayName = [displayName cStringUsingEncoding:NSUTF8StringEncoding];

	EOS_Connect_Credentials Credentials = {};
	Credentials.ApiVersion = EOS_CONNECT_CREDENTIALS_API_LATEST;
	Credentials.Token = cstrToken;
	Credentials.Type = EOS_EExternalCredentialType::EOS_ECT_APPLE_ID_TOKEN;

	EOS_Connect_UserLoginInfo UserLoginInfo = {};
	UserLoginInfo.ApiVersion = EOS_CONNECT_USERLOGININFO_API_LATEST;
	UserLoginInfo.DisplayName = cstrDisplayName;						// EOS_CONNECT_USERLOGININFO_DISPLAYNAME_MAX_LENGTH

	EOS_Connect_LoginOptions Options = {};
	Options.ApiVersion = EOS_CONNECT_LOGIN_API_LATEST;
	Options.Credentials = &Credentials;
	Options.UserLoginInfo = &UserLoginInfo;

	EOS_HPlatform platform = *GPlatforms.begin();
	EOS_HConnect ConnectHandle = EOS_Platform_GetConnectInterface(platform);

	LoginCompletionCB = completion;
	EOS_Connect_Login(ConnectHandle, &Options, nullptr, ConnectLoginCompleteCb);
}

/** Callback to handle result of attempting a login with and Apple ID Token
 *  If the user is invalid, we create a new user for the given credentials
 *  NOTE: See the EOS Connect Interface for more detailed information regarding creating users and account linking
 *  Will return the result to the applications supplied callback, unless we are creating a user */
void EOS_CALL ConnectLoginCompleteCb(const EOS_Connect_LoginCallbackInfo* Info)
{
	assert(Info != NULL);

	os_log(OS_LOG_DEFAULT, "LoginWithAppleIDToken: Result=%s", EOS_EResult_ToString(Info->ResultCode));
	bool bSuccessful = Info->ResultCode == EOS_EResult::EOS_Success;

	if (bSuccessful) {
		ProductLocalUserId = Info->LocalUserId;
	}
	else if (Info->ResultCode == EOS_EResult::EOS_InvalidUser) {
		os_log(OS_LOG_DEFAULT, "LoginWithAppleIDToken: Creating user");

		EOS_Connect_CreateUserOptions Options = {};
		Options.ApiVersion = EOS_CONNECT_CREATEUSER_API_LATEST;
		Options.ContinuanceToken = Info->ContinuanceToken;

		EOS_HPlatform platform = *GPlatforms.begin();
		EOS_HConnect ConnectHandle = EOS_Platform_GetConnectInterface(platform);
		EOS_Connect_CreateUser(ConnectHandle, &Options, nullptr, ConnectCreateUserCompleteCb);
		return;
	}

	LoginCompletionCB(Info->ResultCode);
}

/** Callback to handle result of attempting to create a new user with and Apple ID Token
 *  Will return the result to the applications supplied callback */
void EOS_CALL ConnectCreateUserCompleteCb(const EOS_Connect_CreateUserCallbackInfo* Info)
{
	assert(Info != NULL);

	os_log(OS_LOG_DEFAULT, "LoginWithAppleIDToken: Create user Result=%s", EOS_EResult_ToString(Info->ResultCode));
	bool bSuccessful = Info->ResultCode == EOS_EResult::EOS_Success;

	if (bSuccessful) {
		ProductLocalUserId = Info->LocalUserId;
	}

	LoginCompletionCB(Info->ResultCode);
}

/** Attempt to logout of the EOS Auth Interface
 *  If any stored secure credentials exist on the device, they will also be removed */
+ (void) Logout: (nonnull LogoutCompletion) completion
{
    os_log(OS_LOG_DEFAULT, "Logout:");

    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(platform);

    EOS_Auth_LogoutOptions LogoutOptions = {};
    LogoutOptions.ApiVersion = EOS_AUTH_LOGOUT_API_LATEST;
    LogoutOptions.LocalUserId = LocalUserId;

    LogoutCompletionCB = completion;
    EOS_Auth_Logout(AuthHandle, &LogoutOptions, nullptr, AuthLogoutCb);
}

/** Callback to handle result of attempting a logout
 *  Will return the result to the applications supplied callback */
void EOS_CALL AuthLogoutCb(const EOS_Auth_LogoutCallbackInfo* Info)
{
    assert(Info != NULL);

    os_log(OS_LOG_DEFAULT, "Logout: Result=%s", EOS_EResult_ToString(Info->ResultCode));
    bool bSuccessful = Info->ResultCode == EOS_EResult::EOS_Success;

    if (bSuccessful) {
        LocalUserId = nullptr;

        // Release any data returned to us from GetLoggedInDisplayName
        if (LocalUserInfo != nullptr) {
            EOS_UserInfo_Release(LocalUserInfo);
            LocalUserInfo = nullptr;
        }
    }

    // Delete any stored secure credentials, now that we have logged out
    os_log(OS_LOG_DEFAULT, "Logout: Delete persistent auth");
    [EOSWrapper DeletePersistentAuth: ^(EOS_EResult Result)
    {
        LogoutCompletionCB(Result);
    }];
}

/** Check if we are logged into the EOS Auth Interface */
+ (BOOL) LoggedInViaAuthInterface
{
	if (LocalUserId == nullptr) {
		return false;
	}

	EOS_HPlatform platform = *GPlatforms.begin();
	EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(platform);

	EOS_ELoginStatus LoginStatus = EOS_Auth_GetLoginStatus(AuthHandle, LocalUserId);

	return LoginStatus == EOS_ELoginStatus::EOS_LS_LoggedIn;
}

/** Check if we are logged into the EOS Connect Interface */
+ (BOOL) LoggedInViaConnectInterface
{
	if (ProductLocalUserId == nullptr) {
		return false;
	}

	EOS_HPlatform platform = *GPlatforms.begin();
	EOS_HConnect ConnectHandle = EOS_Platform_GetConnectInterface(platform);

	EOS_ELoginStatus LoginStatus = EOS_Connect_GetLoginStatus(ConnectHandle, ProductLocalUserId);

	return LoginStatus == EOS_ELoginStatus::EOS_LS_LoggedIn;
}

/** An example of obtaining the display name for the user currently logged into the EOS Auth Interface */
+ (nonnull NSString*) GetLoggedInDisplayName
{
    os_log(OS_LOG_DEFAULT, "GetLoggedInDisplayName:");

    if (LocalUserId == nullptr) {
        os_log(OS_LOG_DEFAULT, "GetLoggedInDisplayName: EOS_EpicAccountId is null ");
        return [[NSString alloc] init];
    }

    // Release any data returned to us from a previous call to GetLoggedInDisplayName
    if (LocalUserInfo != nullptr) {
        EOS_UserInfo_Release(LocalUserInfo);
        LocalUserInfo = nullptr;
    }

    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HUserInfo UserInfoHandle = EOS_Platform_GetUserInfoInterface(platform);

    EOS_UserInfo_CopyUserInfoOptions CopyUserInfoOptions = {};
    CopyUserInfoOptions.ApiVersion = EOS_USERINFO_COPYUSERINFO_API_LATEST;
    CopyUserInfoOptions.LocalUserId = LocalUserId;
    CopyUserInfoOptions.TargetUserId = LocalUserId;

    EOS_EResult ResultCode = EOS_UserInfo_CopyUserInfo(UserInfoHandle, &CopyUserInfoOptions, &LocalUserInfo);

    bool bSuccessful = ResultCode == EOS_EResult::EOS_Success;

    if (bSuccessful) {
        os_log(OS_LOG_DEFAULT, "GetLoggedInDisplayName: DisplayName=%s", (LocalUserInfo->DisplayName) ? LocalUserInfo->DisplayName : "");
        if (LocalUserInfo->DisplayName) {
            return [NSString stringWithUTF8String: LocalUserInfo->DisplayName];
        }
    }

    // Return the DisplayName
    return [[NSString alloc] init];
}

/** An example of obtaining the display name for the user currently logged into the EOS Auth Interface */
+ (nonnull NSString*) GetAccountId
{
    os_log(OS_LOG_DEFAULT, "GetAccountId:");

    if (LocalUserId == nullptr) {
        os_log(OS_LOG_DEFAULT, "GetAccountId: EOS_EpicAccountId is null ");
        return [[NSString alloc] init];
    }
    
    char buffer[EOS_EPICACCOUNTID_MAX_LENGTH+1] = { '\0' };
    int32_t length = EOS_EPICACCOUNTID_MAX_LENGTH+1;
    EOS_EResult result = EOS_EpicAccountId_ToString(LocalUserId, buffer, &length);
    if (result != EOS_EResult::EOS_Success) {
        os_log(OS_LOG_DEFAULT, "GetAccountId: Error copying account id: %s", EOS_EResult_ToString(result));
        return [[NSString alloc] init];
    }
    
    os_log(OS_LOG_DEFAULT, "GetAccountId: AccountId=%s", buffer);
    return [NSString stringWithUTF8String: buffer];
}

/** An example of obtaining the display name for the user currently logged into the EOS Auth Interface */
+ (nonnull NSString*) GetAuthToken
{
    os_log(OS_LOG_DEFAULT, "GetAuthToken:");

    if (LocalUserId == nullptr) {
        os_log(OS_LOG_DEFAULT, "GetAuthToken: EOS_EpicAccountId is null ");
        return [[NSString alloc] init];
    }
    
    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(platform);
    
    EOS_Auth_IdToken* token = nullptr;
    EOS_Auth_CopyIdTokenOptions options = { 0 };
    options.ApiVersion = EOS_AUTH_COPYIDTOKEN_API_LATEST;
    options.AccountId = LocalUserId;

    // User must be logged in to succeed.
    EOS_EResult ResultCode = EOS_Auth_CopyIdToken(AuthHandle, &options, &token);
    if (ResultCode != EOS_EResult::EOS_Success) {
        os_log(OS_LOG_DEFAULT, "GetAuthtoken: Error copying id token: %s", EOS_EResult_ToString(ResultCode));
        return [[NSString alloc] init];
    }
    return [NSString stringWithUTF8String:token->JsonWebToken];
}

/** Register for updates that reflect changes in the users login status for the EOS Auth Interface */
+ (void) AddNotifyLoginStatusChanged: (nonnull NotifyLoginStatusChangedCompletion) completion
{
    os_log(OS_LOG_DEFAULT, "AddNotifyLoginStatusChanged: Register");

    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(platform);

    EOS_Auth_AddNotifyLoginStatusChangedOptions NotifyLoginStatusChangedOptions = {};
    NotifyLoginStatusChangedOptions.ApiVersion = EOS_AUTH_ADDNOTIFYLOGINSTATUSCHANGED_API_LATEST;

    NotifyLoginStatusChangedCompletionCB = completion;
    NotifyLoginStatusChanged = EOS_Auth_AddNotifyLoginStatusChanged(AuthHandle, &NotifyLoginStatusChangedOptions, nullptr, AuthNotifyLoginStatusChangedCb);
}

/** Callback to handle login status changes
 *  Will return the result to the applications supplied callback */
void EOS_CALL AuthNotifyLoginStatusChangedCb(const EOS_Auth_LoginStatusChangedCallbackInfo* Info)
{
    assert(Info != NULL);

    os_log(OS_LOG_DEFAULT, "NotifyLoginStatusChanged: LoggedIn=%d, PrevState=%d", (Info->CurrentStatus == EOS_ELoginStatus::EOS_LS_LoggedIn), (Info->PrevStatus == EOS_ELoginStatus::EOS_LS_LoggedIn));

    NotifyLoginStatusChangedCompletionCB((Info->CurrentStatus == EOS_ELoginStatus::EOS_LS_LoggedIn), (Info->PrevStatus == EOS_ELoginStatus::EOS_LS_LoggedIn));
}

/** Unregister for login status updates for the EOS Auth Interface */
+ (void) RemoveNotifyLoginStatusChanged
{
    os_log(OS_LOG_DEFAULT, "RemoveNotifyLoginStatusChanged: Unregister");

    if (NotifyLoginStatusChanged == 0) {
        return;
    }

    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(platform);

    NotifyLoginStatusChangedCompletionCB = nil;
    EOS_Auth_RemoveNotifyLoginStatusChanged(AuthHandle, NotifyLoginStatusChanged);

    NotifyLoginStatusChanged = 0;
}

// MARK: - Network Status

/** Send sgnal SDK of an updated to the Network Status */
+ (EOS_EResult) SignalUpdateToNetworkStatus: (EOS_ENetworkStatus) status
{
    os_log(OS_LOG_DEFAULT, "SetNetworkStatus:");
    EOS_HPlatform platform = *GPlatforms.begin();
      
    return EOS_Platform_SetNetworkStatus(platform, status);
}

// MARK: - Application Status

/** Send sgnal SDK of an updated to the Application Status */
+ (EOS_EResult) SignalUpdateToApplicationStatus: (EOS_EApplicationStatus) status
{
    os_log(OS_LOG_DEFAULT, "SetApplicationStatus:");
    EOS_HPlatform platform = *GPlatforms.begin();

    return EOS_Platform_SetApplicationStatus(platform, status);
}

// MARK: - Private Methods

/** Delete secure stored credentials on this device
 *  Used internally as part of logout or failed login with stored credential flows */
+ (void) DeletePersistentAuth: (nonnull void (^)(EOS_EResult Result)) completion
{
    os_log(OS_LOG_DEFAULT, "DeletePersistentAuth:");

    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(platform);

    EOS_Auth_DeletePersistentAuthOptions DeletePersistentAuthOptions = {};
    DeletePersistentAuthOptions.ApiVersion = EOS_AUTH_DELETEPERSISTENTAUTH_API_LATEST;

    DeletePersistentAuthCompletionCB = completion;
    EOS_Auth_DeletePersistentAuth(AuthHandle, &DeletePersistentAuthOptions, nullptr, AuthDeletePersistentAuthCb);
}

/** Callback to handle result of attempting to delete any secure credentials on the device
 *  Will return the result to the supplied callback */
void EOS_CALL AuthDeletePersistentAuthCb(const EOS_Auth_DeletePersistentAuthCallbackInfo* Info)
{
    assert(Info != NULL);

    os_log(OS_LOG_DEFAULT, "DeletePersistentAuth: Result=%s", EOS_EResult_ToString(Info->ResultCode));

    DeletePersistentAuthCompletionCB(Info->ResultCode);
}

// MARK: - ECom Methods
NSObject* safeString(const char* cstr) {
    if (cstr) {
        return [NSString stringWithUTF8String:cstr];
    }
    return [NSNull null];
}

NSObject* asTimestamp(std::time_t time) {
    if (time != -1) {
        char buffer[sizeof "2025-12-31T01:02:03Z"];
        std::strftime(buffer, (sizeof buffer), "%FT%TZ", std::gmtime(&time));
        return safeString(buffer);
    }
    return [NSNull null];
}

NSDictionary* EosCopyEntitlement(EOS_Ecom_Entitlement* Entitlement) {
    os_log(OS_LOG_DEFAULT, "New Entitlement : %s (%s) : %s",
    Entitlement->EntitlementName,
    Entitlement->EntitlementId,
    Entitlement->bRedeemed ? "redeemed" : "not redeemed");
    
    return @{
        @"Name": safeString(Entitlement->EntitlementName),
        @"Id": safeString(Entitlement->EntitlementId),
        @"CatalogItemId": safeString(Entitlement->CatalogItemId),
        @"Redeemed": @(Entitlement->bRedeemed == EOS_TRUE),
        @"EndTimestamp": asTimestamp(Entitlement->EndTimestamp)
    };
}

void EOS_CALL EosQueryEntitlementsCallback(const EOS_Ecom_QueryEntitlementsCallbackInfo* Data) {
    if (Data->ResultCode != EOS_EResult::EOS_Success) {
        EntitlementsCompletionCB(Data->ResultCode, nil);
    } else {
        EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(*GPlatforms.begin());
        EOS_Ecom_GetEntitlementsCountOptions options = { 0 };
        options.ApiVersion = EOS_ECOM_GETENTITLEMENTSCOUNT_API_LATEST;
        options.LocalUserId = LocalUserId;
        const uint32_t numOfEntitlements = EOS_Ecom_GetEntitlementsCount(EcomHandle, &options);
        os_log(OS_LOG_DEFAULT, "Ecom Query: Found %d entitlements", numOfEntitlements);
        EOS_Ecom_CopyEntitlementByIndexOptions entitlementOptions = { 0 };
        entitlementOptions.ApiVersion = EOS_ECOM_COPYENTITLEMENTBYINDEX_API_LATEST;
        entitlementOptions.LocalUserId = LocalUserId;
        NSMutableArray *nsEntitlements= [[NSMutableArray alloc] init];
        for(int i = 0; i < numOfEntitlements; ++i) {
            EOS_Ecom_Entitlement* entitlement = nullptr;
            entitlementOptions.EntitlementIndex = i;
            const EOS_EResult result = EOS_Ecom_CopyEntitlementByIndex(EcomHandle, &entitlementOptions, &entitlement);
            switch(result) {
                case EOS_EResult::EOS_Success:
                case EOS_EResult::EOS_Ecom_EntitlementStale:
                {
                    [nsEntitlements addObject: EosCopyEntitlement(entitlement)];
                    EOS_Ecom_Entitlement_Release(entitlement);
                }
                break;
                default:
                {
                    os_log(OS_LOG_DEFAULT, "Error retrieving entitlement %i: %s", i, EOS_EResult_ToString(result));
                }
            }
        }
        EntitlementsCompletionCB(Data->ResultCode, @{@"entitlements": [NSArray arrayWithArray:nsEntitlements]});
    }
    EntitlementsCompletionCB = nil;
}

NSString* EosItemTypeToString(EOS_EEcomItemType type) {
    switch (type) {
        case EOS_EEcomItemType::EOS_EIT_Durable:
            return @"Durable";
        case EOS_EEcomItemType::EOS_EIT_Consumable:
            return @"Consumable";
        case EOS_EEcomItemType::EOS_EIT_Other:
        default:
            return @"Other";
    }
}

NSDictionary* EosCopyItem(EOS_Ecom_CatalogItem* item) {
    os_log(OS_LOG_DEFAULT, ">> item %s - %s", item->Id, item->TitleText);
    return @{
        @"Id": safeString(item->Id),
        @"Title": safeString(item->TitleText),
        @"Description": safeString(item->DescriptionText),
        @"LongDescription": safeString(item->LongDescriptionText),
        @"TechnicalDetails": safeString(item->TechnicalDetailsText),
        @"Developer": safeString(item->DeveloperText),
        @"ItemType": EosItemTypeToString(item->ItemType),
        @"EntitlementName": safeString(item->EntitlementName),
        @"EntitlementEnd": asTimestamp(item->EntitlementEndTimestamp),
    };
}

NSArray* EosCopyItems(EOS_HEcom EcomHandle, EOS_Ecom_CatalogOffer* offer) {
    EOS_Ecom_GetOfferItemCountOptions options = { 0 };
    options.ApiVersion = EOS_ECOM_GETOFFERITEMCOUNT_API_LATEST;
    options.LocalUserId = LocalUserId;
    options.OfferId = offer->Id;
    const uint32_t numOfItems = EOS_Ecom_GetOfferItemCount(EcomHandle, &options);
    os_log(OS_LOG_DEFAULT, "Ecom Query: Found %d items in offer %s", numOfItems, offer->Id);
    EOS_Ecom_CopyOfferItemByIndexOptions itemOptions = { 0 };
    itemOptions.ApiVersion = EOS_ECOM_COPYOFFERITEMBYINDEX_API_LATEST;
    itemOptions.LocalUserId = LocalUserId;
    itemOptions.OfferId = offer->Id;
    NSMutableArray* nsItems = [[NSMutableArray alloc] init];
    for(int i = 0; i < numOfItems; ++i) {
        EOS_Ecom_CatalogItem* item = nullptr;
        itemOptions.ItemIndex = i;
        const EOS_EResult result = EOS_Ecom_CopyOfferItemByIndex(EcomHandle, &itemOptions, &item);
        if (result != EOS_EResult::EOS_Success) {
            os_log(OS_LOG_DEFAULT, "Error retrieving item %d from offer %s: %s", i, offer->Id, EOS_EResult_ToString(result));
        } else {
            [nsItems addObject: EosCopyItem(item)];
            EOS_Ecom_CatalogItem_Release(item);
        }
    }
    return [NSArray arrayWithArray:nsItems];
}

NSDictionary* EosCopyOffer(EOS_HEcom EcomHandle, EOS_Ecom_CatalogOffer* offer) {
    os_log(OS_LOG_DEFAULT, "> Offer %s - %s", offer->Id, offer->TitleText);
    NSMutableDictionary* nsOffer = [[NSMutableDictionary alloc] init];
    [nsOffer addEntriesFromDictionary:@{
        @"Id": safeString(offer->Id),
        @"Title": safeString(offer->TitleText),
        @"Description": safeString(offer->DescriptionText),
        @"LongDescription": safeString(offer->LongDescriptionText),
        @"Currency": safeString(offer->CurrencyCode),
        @"Available": @(!!offer->bAvailableForPurchase),
    }];
    if (offer->PriceResult == EOS_EResult::EOS_Success) {
        [nsOffer addEntriesFromDictionary:@{
            @"Discount": @(offer->DiscountPercentage),
            @"OriginalPrice": @(offer->OriginalPrice64),
            @"CurrentPrice": @(offer->CurrentPrice64),
            @"DecimalPoint": @(offer->DecimalPoint),
        }];
    } else {
        os_log(OS_LOG_DEFAULT, "Error for price of %s: %s", offer->Id, EOS_EResult_ToString(offer->PriceResult));
    }
    if (offer->ExpirationTimestamp != EOS_ECOM_CATALOGOFFER_EXPIRATIONTIMESTAMP_UNDEFINED) {
        [nsOffer setObject: asTimestamp(offer->ExpirationTimestamp) forKey: @"Expiration"];
    }
    if (offer->ReleaseDateTimestamp != EOS_ECOM_CATALOGOFFER_RELEASEDATETIMESTAMP_UNDEFINED) {
        [nsOffer setObject:asTimestamp(offer->ReleaseDateTimestamp) forKey: @"ReleaseDate"];
    }
    if (offer->EffectiveDateTimestamp != EOS_ECOM_CATALOGOFFER_EFFECTIVEDATETIMESTAMP_UNDEFINED) {
        [nsOffer setObject:asTimestamp(offer->EffectiveDateTimestamp) forKey: @"EffectiveDate"];
    }
    [nsOffer setObject: EosCopyItems(EcomHandle, offer) forKey:@"Items"];
    return [NSDictionary dictionaryWithDictionary:nsOffer];
}

void EosQueryOffersCallback(const EOS_Ecom_QueryOffersCallbackInfo* Data) {
    if (Data->ResultCode != EOS_EResult::EOS_Success) {
        OffersCompletionCB(Data->ResultCode, nil);
    } else {
        EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(*GPlatforms.begin());
        EOS_Ecom_GetOfferCountOptions options = { 0 };
        options.ApiVersion = EOS_ECOM_GETOFFERCOUNT_API_LATEST;
        options.LocalUserId = LocalUserId;
        const uint32_t numOfOffers = EOS_Ecom_GetOfferCount(EcomHandle, &options);
        os_log(OS_LOG_DEFAULT, "Ecom Query: Found %d offers", numOfOffers);
        EOS_Ecom_CopyOfferByIndexOptions offerOptions = { 0 };
        offerOptions.ApiVersion = EOS_ECOM_COPYOFFERBYINDEX_API_LATEST;
        offerOptions.LocalUserId = LocalUserId;
        NSMutableArray* nsOffers = [[NSMutableArray alloc] init];
        for(int i = 0; i < numOfOffers; ++i) {
            EOS_Ecom_CatalogOffer* offer = nullptr;
            offerOptions.OfferIndex = i;
            const EOS_EResult result = EOS_Ecom_CopyOfferByIndex(EcomHandle, &offerOptions, &offer);
            if (result != EOS_EResult::EOS_Success) {
                os_log(OS_LOG_DEFAULT, "Error retrieving offer %i: %s", i, EOS_EResult_ToString(result));
            } else {
                [nsOffers addObject: EosCopyOffer(EcomHandle, offer)];
                EOS_Ecom_CatalogOffer_Release(offer);
            }
        }
        OffersCompletionCB(Data->ResultCode, @{@"offers": [NSArray arrayWithArray:nsOffers]});
    }
    OffersCompletionCB = nil;
}

void CheckoutCompleteCallbackFn(const EOS_Ecom_CheckoutCallbackInfo* Data) {
    if (Data->ResultCode != EOS_EResult::EOS_Success) {
        CheckoutCompletionCB(Data->ResultCode, nil);
    } else {
        NSMutableArray* nsEntitlements = [[NSMutableArray alloc] init];
        // Some checkout can returned empty;
        if (Data->TransactionId) {
            EOS_Ecom_HTransaction TransactionHandle;
            EOS_Ecom_CopyTransactionByIdOptions CopyTransactionOptions{ 0 };
            CopyTransactionOptions.ApiVersion = EOS_ECOM_COPYTRANSACTIONBYID_API_LATEST;
            CopyTransactionOptions.LocalUserId = Data->LocalUserId;
            CopyTransactionOptions.TransactionId = Data->TransactionId;
    
            EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(*GPlatforms.begin());
            auto txnCopyResult = EOS_Ecom_CopyTransactionById(EcomHandle, &CopyTransactionOptions, &TransactionHandle);
            if (txnCopyResult != EOS_EResult::EOS_Success) {
                os_log(OS_LOG_DEFAULT, "Error getting transaction '%s': %s", Data->TransactionId, EOS_EResult_ToString(txnCopyResult));
                CheckoutCompletionCB(txnCopyResult, nil);
                CheckoutCompletionCB = nil;
                return;
            } else {
                EOS_Ecom_Transaction_GetEntitlementsCountOptions CountOptions{ 0 };
                CountOptions.ApiVersion = EOS_ECOM_TRANSACTION_GETENTITLEMENTSCOUNT_API_LATEST;
                uint32_t EntitlementCount = EOS_Ecom_Transaction_GetEntitlementsCount(TransactionHandle, &CountOptions);
    
                os_log(OS_LOG_DEFAULT, "New entitlements: %d", EntitlementCount);
    
                EOS_Ecom_Transaction_CopyEntitlementByIndexOptions IndexOptions{ 0 };
                IndexOptions.ApiVersion = EOS_ECOM_TRANSACTION_COPYENTITLEMENTBYINDEX_API_LATEST;
                for (IndexOptions.EntitlementIndex = 0; IndexOptions.EntitlementIndex < EntitlementCount; ++IndexOptions.EntitlementIndex)
                {
                    EOS_Ecom_Entitlement* Entitlement;
                    EOS_EResult CopyResult = EOS_Ecom_Transaction_CopyEntitlementByIndex(TransactionHandle, &IndexOptions, &Entitlement);
                    switch (CopyResult)
                    {
                    case EOS_EResult::EOS_Success:
                    case EOS_EResult::EOS_Ecom_EntitlementStale:
                    {
                        [nsEntitlements addObject:EosCopyEntitlement(Entitlement)];
                        EOS_Ecom_Entitlement_Release(Entitlement);
                    }
                    break;
                    default:
                    {
                        os_log(OS_LOG_DEFAULT, "Invalid entitlement %d: %s",
                            IndexOptions.EntitlementIndex, EOS_EResult_ToString(CopyResult));
                    }
                    break;
                    }
                }
                EOS_Ecom_Transaction_Release(TransactionHandle);
            }
        }
        CheckoutCompletionCB(Data->ResultCode, @{
            @"TransactionId": safeString(Data->TransactionId),
            @"NewEntitlements": [NSArray arrayWithArray:nsEntitlements],
        });
    }
    CheckoutCompletionCB = nil;
}

+ (void) QueryEntitlements: (nonnull EntitlementsCompletion) completion {
    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(platform);
    EOS_Ecom_QueryEntitlementsOptions options = { 0 };
    options.ApiVersion = EOS_ECOM_QUERYENTITLEMENTS_API_LATEST;
    options.LocalUserId = LocalUserId;
    // Query all entitlements
    options.EntitlementNames = nullptr;
    options.EntitlementNameCount = 0;
    // TODO: Make it an option
    options.bIncludeRedeemed = true;
    EntitlementsCompletionCB = completion;
    EOS_Ecom_QueryEntitlements(EcomHandle, &options, NULL, &EosQueryEntitlementsCallback);
}

+ (void) QueryOffers: (nonnull OffersCompletion) completion {
    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(platform);
    EOS_Ecom_QueryOffersOptions options = { 0 };
    options.ApiVersion = EOS_ECOM_QUERYOFFERS_API_LATEST;
    options.LocalUserId = LocalUserId;
    OffersCompletionCB = completion;
    EOS_Ecom_QueryOffers(EcomHandle, &options, NULL, &EosQueryOffersCallback);
}

+ (void) Checkout: (nonnull NSArray*)offers completion: (nonnull CheckoutCompletion) completion {
    const NSUInteger length = offers.count;
    std::vector<EOS_Ecom_CheckoutEntry> entries;
    std::vector<std::string> ids;
    for(NSUInteger i = 0; i < length; ++i) {
        NSString* nsOfferId = [offers objectAtIndex:i];
        const std::string utfOfferId{[nsOfferId cStringUsingEncoding:NSUTF8StringEncoding]};
        ids.push_back(utfOfferId);
        os_log(OS_LOG_DEFAULT, "Checking out offer %s [%d/%d]", utfOfferId.c_str(), (unsigned)i+1, (unsigned)length);
        EOS_Ecom_CheckoutEntry entry;
        entry.ApiVersion = EOS_ECOM_CHECKOUTENTRY_API_LATEST;
        entry.OfferId = ids.back().c_str();
        entries.emplace_back(entry);
    }
    EOS_Ecom_CheckoutOptions options = { 0 };
    options.ApiVersion = EOS_ECOM_CHECKOUT_API_LATEST;
    options.LocalUserId = LocalUserId;
    options.EntryCount = (unsigned)length;
    // Note: The entries are copied back internally immediately before the API calls returned.
    options.Entries = entries.data();
    // TODO: Add it as an option
    options.PreferredOrientation = EOS_ECheckoutOrientation::EOS_ECO_Default;
    EOS_HPlatform platform = *GPlatforms.begin();
    EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(platform);
    CheckoutCompletionCB = completion;
    EOS_Ecom_Checkout(EcomHandle, &options, NULL, CheckoutCompleteCallbackFn);
}

@end
