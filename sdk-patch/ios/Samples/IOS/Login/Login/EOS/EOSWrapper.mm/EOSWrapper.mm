// Copyright Epic Games, Inc. All Rights Reserved.

#import <Foundation/Foundation.h>
#import <os/log.h>

#import "EOSWrapper.h"
#import "ReservedPlatformOptions.h"

#import "eos_sdk.h"
#import "eos_auth.h"
#import "eos_connect.h"
#import "eos_logging.h"
#import "eos_init.h"
#import "eos_userinfo.h"
#import "eos_ios.h"

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

static void (^DeletePersistentAuthCompletionCB)(EOS_EResult Result) = nil;

static EOS_NotificationId NotifyLoginStatusChanged = 0;

/** Initialize the EOS SDK for use before we call any other functions, normally during application launching
 *  We supply the applications product name and current version number
 *  NOTE: initializeSDK and shutdownSDK must be called on the main thread */
+ (EOS_EResult) InitializeSDK: (NSString*) ProductName version:(NSString*) version
{
	EOS_InitializeOptions SDKOptions {0};
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
	EOS_Platform_Options PlatformOptions {0};
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
	LoginOptions.ScopeFlags = EOS_EAuthScopeFlags::EOS_AS_BasicProfile | EOS_EAuthScopeFlags::EOS_AS_Country;
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

	EOS_Connect_Credentials Credentials{};
	Credentials.ApiVersion = EOS_CONNECT_CREDENTIALS_API_LATEST;
	Credentials.Token = cstrToken;
	Credentials.Type = EOS_EExternalCredentialType::EOS_ECT_APPLE_ID_TOKEN;

	EOS_Connect_UserLoginInfo UserLoginInfo{};
	UserLoginInfo.ApiVersion = EOS_CONNECT_USERLOGININFO_API_LATEST;
	UserLoginInfo.DisplayName = cstrDisplayName;						// EOS_CONNECT_USERLOGININFO_DISPLAYNAME_MAX_LENGTH

	EOS_Connect_LoginOptions Options{};
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

		EOS_Connect_CreateUserOptions Options{};
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

@end
