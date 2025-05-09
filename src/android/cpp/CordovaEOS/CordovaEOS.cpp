#include <jni.h>
#include <string>
#include <vector>
#include <unordered_set>
#include <ctime>
#include <cstdio>
#include <eos_init.h>
#include <eos_sdk.h>
#include <eos_auth.h>
#include <eos_connect.h>
#include <eos_logging.h>
#include <eos_auth_types.h>
#include <eos_userinfo.h>
#include <eos_ui.h>
#include <eos_version.h>
#include <eos_ecom.h>
#include "Android/eos_android.h"

bool IsSDKInitialized = false;
EOS_HPlatform PlatformHandle = nullptr;
JNIEnv *LocalENV = nullptr;
jclass GlobalRefCordovaEOSClass = nullptr;
jobject GlobalRefCordovaEOSInstance = nullptr;

static EOS_EpicAccountId LocalUserId = nullptr;
static EOS_UserInfo *LocalUserInfo = nullptr;
static EOS_NotificationId NotifyLoginStatusChangedId = EOS_INVALID_NOTIFICATIONID;

void LogText(jstring Text) {
    jmethodID MethodID = LocalENV->GetMethodID(GlobalRefCordovaEOSClass, "LogText", "(Ljava/lang/String;)V");
    LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, Text);
}

/** Call Java LogText method to display log in Android view */
void OS_LOG(const char *Text) {
    if (Text) {
        LogText(LocalENV->NewStringUTF(Text));
    }
}

void OS_LOG_ERROR(const char *Message, EOS_EResult ResultCode) {
    const unsigned int MAX_LEN = 1023;
    char formattedMessage[MAX_LEN+1] = { '\0' };
    formattedMessage[MAX_LEN] = '\0';
    std::snprintf(formattedMessage, MAX_LEN, Message, EOS_EResult_ToString(ResultCode));
    OS_LOG(formattedMessage);
}

void LogMessage(const EOS_LogMessage* Message) {
    const unsigned int MAX_LEN = 1023;
    char formattedMessage[MAX_LEN+1] = { '\0' };
    formattedMessage[MAX_LEN] = '\0';
    std::snprintf(formattedMessage, MAX_LEN, "%s: %s", Message->Category, Message->Message);
    OS_LOG(formattedMessage);
}

class JsonValue {
    enum class JsonType {
        Null,
        Boolean,
        Number,
        String,
        Object,
        Array
    };
    private:
        JsonType type;
        std::string value;
        std::vector<JsonValue> array;
        JsonValue(JsonType type, std::string value = "")
        : type(type)
        , value(std::move(value)){}
        std::string arrayToJson() const {
            if (array.size() > 0) {
                std::string result = "[";
                for(const JsonValue& item : array) {
                    result += item.toJson() + ",";
                }
                // Replace last ','
                result[result.size()-1] = ']';
                return result;
            } else {
                return "[]";
            }
        }
        std::string objectToJson() const {
            if (array.size() > 0) {
                std::string result = "{";
                for(int i = 0; i < array.size(); i += 2) {
                    result += array[i].toJson() + ":" + array[i+1].toJson() + ",";
                }
                // Replace last ','
                result[result.size()-1] = '}';
                return result;
            } else {
                return "{}";
            }

        }
        static std::string escape(const std::string& value) {
            std::string result;
            for(const char c: value) {
                switch(c) {
                    // skip \u and \/
                    case '\\':
                        result.append("\\\\");
                        break;
                    case '"':
                        result.append("\\\"");
                        break;
                    case '\n':
                        result.append("\\n");
                        break;
                    case '\t':
                        result.append("\\t");
                        break;
                    case '\b':
                        result.append("\\b");
                        break;
                    case '\f':
                        result.append("\\f");
                        break;
                    case '\r':
                        result.append("\\r");
                        break;
                    default:
                        result.push_back(c);
                }
            }
            return result;
        }
    public:
        JsonType getType() const;

        static JsonValue MakeObject() {
            return JsonValue(JsonType::Object);
        };
        static JsonValue MakeArray() {
            return JsonValue(JsonType::Array);
        };
        static JsonValue MakeNull() {
            return JsonValue(JsonType::Null);
        };
        static JsonValue MakeString(const char* value) {
            if (value != nullptr) {
                return MakeEscapedString(escape(value));
            } else {
                OS_LOG("trying to serialized null string");
                return MakeNull();
            }
        };
        static JsonValue MakeString(const std::string& value) {
            return MakeEscapedString(escape(value));
        };
        static JsonValue MakeEscapedString(const std::string & escapedValue) {
            return JsonValue(JsonType::String, "\"" + escapedValue + "\"");
        }
        template <class NumberType>
        static JsonValue MakeNumber(NumberType value) {
            return JsonValue(JsonType::Number, std::to_string(value));
        };
        static JsonValue MakeBoolean(bool value) {
            return JsonValue(JsonType::Boolean, value ? "true" : "false");
        }
        static JsonValue MakeTimestamp(std::time_t time) {
            if (time != -1) {
                char buffer[sizeof "2025-12-31T01:02:03Z"];
                std::strftime(buffer, (sizeof buffer), "%FT%TZ", std::gmtime(&time));
                return MakeEscapedString(buffer);    
            }
            return MakeNull();
        }

        std::string toJson() const {
            switch(type) {
                case JsonType::Boolean:
                case JsonType::Number:
                case JsonType::String:
                    return value;
                case JsonType::Null:
                    return "null";
                case JsonType::Array:
                    return arrayToJson();
                case JsonType::Object:
                    return objectToJson();
            }
        }
        // Array methods
        void Append(JsonValue value) {
            if (type != JsonType::Array) {
                OS_LOG("Invalid json type for array!");
                return;
            }
            array.emplace_back(std::move(value));
        }
        // Object methods
        void AddProperty(std::string name, JsonValue value) {
            if (type != JsonType::Object) {
                OS_LOG("Invalid json type for object!");
                return;
            }
            array.emplace_back(MakeString(std::move(name)));
            array.emplace_back(std::move(value));
        }
};

void DeletePersistentAuth();

void LoginStateChanged(bool loggedIn) {
    jmethodID MethodID = LocalENV->GetMethodID(GlobalRefCordovaEOSClass, "LoginStateChanged", "(Z)V");
    LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, loggedIn);
}

void LoginInProgress() {
    jmethodID MethodID = LocalENV->GetMethodID(GlobalRefCordovaEOSClass, "LoginInProgress", "()V");
    LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID);
}

void LoginResult(bool success, jobject context) {
    jmethodID MethodID = LocalENV->GetMethodID(GlobalRefCordovaEOSClass, "LoginResult", "(ZLjava/lang/Object;)V");
    LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, success, context);
    LocalENV->DeleteGlobalRef(context);
}


/** An example of obtaining the display name for the user currently logged into the EOS Auth Interface */
std::string GetLoggedInDisplayName() {
    if (PlatformHandle == nullptr) {
        return "";
    }

    EOS_HUserInfo UserInfoHandle = EOS_Platform_GetUserInfoInterface(PlatformHandle);

    /** Release any data returned to us from a previous call to GetLoggedInDisplayName */
    if (LocalUserInfo != nullptr) {
        EOS_UserInfo_Release(LocalUserInfo);
        LocalUserInfo = nullptr;
    }

    EOS_UserInfo_CopyUserInfoOptions CopyUserInfoOptions = { 0 };
    CopyUserInfoOptions.ApiVersion = EOS_USERINFO_COPYUSERINFO_API_LATEST;
    CopyUserInfoOptions.LocalUserId = LocalUserId;
    CopyUserInfoOptions.TargetUserId = LocalUserId;

    EOS_EResult ResultCode = EOS_UserInfo_CopyUserInfo(UserInfoHandle, &CopyUserInfoOptions, &LocalUserInfo);
    bool bSuccessful = ResultCode == EOS_EResult::EOS_Success;
    if (!bSuccessful) {
        OS_LOG_ERROR("Error copying user info: %s", ResultCode);
    }
    return std::string(bSuccessful ? LocalUserInfo->DisplayName : "");
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_GetUsername(JNIEnv *env, jobject thiz) {
    return LocalENV->NewStringUTF(GetLoggedInDisplayName().c_str());
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_GetAccountId(JNIEnv *env, jobject thiz) {
    char accountId[EOS_EPICACCOUNTID_MAX_LENGTH+1] = { 0 };
    int32_t accountIdSize = sizeof accountId;
    // User must be logged in to succeed.
    EOS_EResult ResultCode = EOS_EpicAccountId_ToString(LocalUserId, accountId, &accountIdSize);
    bool bSuccessful = ResultCode == EOS_EResult::EOS_Success;
    if (!bSuccessful) {
        OS_LOG_ERROR("Error converting AccountId: %s", ResultCode);
    }
    return LocalENV->NewStringUTF(bSuccessful ? accountId : "");
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_GetAuthToken(JNIEnv *env, jobject thiz) {
    if (PlatformHandle == nullptr) {
        return LocalENV->NewStringUTF("");
    }

    EOS_HAuth handle = EOS_Platform_GetAuthInterface(PlatformHandle);

    EOS_Auth_IdToken* token = nullptr;
    EOS_Auth_CopyIdTokenOptions options = { 0 };
    options.ApiVersion = EOS_AUTH_COPYIDTOKEN_API_LATEST;
    options.AccountId = LocalUserId;

    // User must be logged in to succeed.
    EOS_EResult ResultCode = EOS_Auth_CopyIdToken(handle, &options, &token);
    if (ResultCode != EOS_EResult::EOS_Success) {
        OS_LOG_ERROR("Error copying id token: %s", ResultCode);
    }
    jstring result = LocalENV->NewStringUTF(ResultCode == EOS_EResult::EOS_Success ? token->JsonWebToken : "");
    if (token != nullptr) {
        EOS_Auth_IdToken_Release(token);
    }
    return result;
}

/** Callback to handle login status changes */
void EOS_CALL AuthNotifyLoginStatusChangedCb(const EOS_Auth_LoginStatusChangedCallbackInfo *Data) {
    if (Data->CurrentStatus == EOS_ELoginStatus::EOS_LS_LoggedIn) {
        LoginStateChanged(true);
    } else if (Data->CurrentStatus == EOS_ELoginStatus::EOS_LS_NotLoggedIn) {
        DeletePersistentAuth();
        LoginStateChanged(false);
    }
}

/** Callback to handle result of attempting a login using the web account portal */
void EOS_CALL AuthLoginCb(const EOS_Auth_LoginCallbackInfo *Data) {
    if (!EOS_EResult_IsOperationComplete(Data->ResultCode)) {
        LoginInProgress();
        return;
    }
    std::string result = std::string("Login Result: ") + EOS_EResult_ToString(Data->ResultCode);
    OS_LOG(result.c_str());
    bool bSuccessful = Data->ResultCode == EOS_EResult::EOS_Success;
    if (bSuccessful) {
        LocalUserId = Data->LocalUserId;
        std::string DisplayName = std::string("DisplayName= ") + GetLoggedInDisplayName();
        OS_LOG(DisplayName.c_str());
    }
    LoginStateChanged(bSuccessful);
    LoginResult(bSuccessful, (jobject)Data->ClientData);
}

/** Callback to handle result of attempting a login with stored secure credentials */
void EOS_CALL PersistentAuthLoginCb(const EOS_Auth_LoginCallbackInfo *Data) {

    if (!EOS_EResult_IsOperationComplete(Data->ResultCode)) {
        LoginInProgress();
        return;
    }

    std::string result = std::string(
            "LoginPersistentAuth: Result=") + EOS_EResult_ToString(Data->ResultCode);
    OS_LOG(result.c_str());
    bool bSuccessful = Data->ResultCode == EOS_EResult::EOS_Success;
    if (bSuccessful) {
        LocalUserId = Data->LocalUserId;
        std::string DisplayName = std::string("DisplayName= ") + GetLoggedInDisplayName();
        OS_LOG(DisplayName.c_str());
    } else {
        // Check the specific error if we fail to complete a persistent login attempt, as we may need to flush any stored secure credentials
        switch (Data->ResultCode) {
            case EOS_EResult::EOS_Canceled:
            case EOS_EResult::EOS_AlreadyPending:
            case EOS_EResult::EOS_TooManyRequests:
            case EOS_EResult::EOS_TimedOut:
            case EOS_EResult::EOS_ServiceFailure:
            case EOS_EResult::EOS_NotFound:
            case EOS_EResult::EOS_InvalidAuth:
                OS_LOG_ERROR("LoginPersistentAuth: Login Failed: %s", Data->ResultCode);
                break;
            default:
                OS_LOG_ERROR("LoginPersistentAuth: Delete persistent auth: %s", Data->ResultCode);
                DeletePersistentAuth();
                break;
        }
    }

    /** Update native UI */
    LoginStateChanged(bSuccessful);
    LoginResult(bSuccessful, (jobject)Data->ClientData);
}

/** Callback to handle result of attempting to delete any secure credentials on the device */
void EOS_CALL AuthDeletePersistentAuthCb(const EOS_Auth_DeletePersistentAuthCallbackInfo *Data) {
    std::string result = std::string("Delete PersistentAuth: Result=") + EOS_EResult_ToString(Data->ResultCode);
    OS_LOG(result.c_str());

    bool bSuccessful = Data->ResultCode == EOS_EResult::EOS_Success;
    if (bSuccessful) {
        LocalUserId = nullptr;
        OS_LOG("Delete successful");
    }
}

/** Callback to handle result of attempting a logout */
void EOS_CALL AuthLogoutCb(const EOS_Auth_LogoutCallbackInfo *Data) {
    bool bSuccessful = Data->ResultCode == EOS_EResult::EOS_Success;
    if (bSuccessful) {
        LocalUserId = nullptr;
        // Release any data returned to us from GetLoggedInDisplayName
        if (LocalUserInfo != nullptr) {
            EOS_UserInfo_Release(LocalUserInfo);
            LocalUserInfo = nullptr;
        }
        // Delete any stored secure credentials, now that we have logged out
        DeletePersistentAuth();
    } else {
        OS_LOG_ERROR("Error logging out: %s", Data->ResultCode);
    }
    LoginResult(bSuccessful, (jobject)Data->ClientData);
}

/** Delete secure stored credentials on this device */
void DeletePersistentAuth() {
    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(PlatformHandle);
    EOS_Auth_DeletePersistentAuthOptions DeletePersistentAuthOptions = { 0 };
    DeletePersistentAuthOptions.ApiVersion = EOS_AUTH_DELETEPERSISTENTAUTH_API_LATEST;
    EOS_Auth_DeletePersistentAuth(AuthHandle, &DeletePersistentAuthOptions, nullptr, AuthDeletePersistentAuthCb);
}

/** Initialize the EOS SDK for use before we call any other functions, normally during application launching
 *  We supply optional internal/external directory */
extern "C" JNIEXPORT jboolean JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_InitializeSDK(
        JNIEnv *env,
        jobject /* this */,
        jstring ProductName,
        jstring ProductVersion,
        jstring Path) {
    if (IsSDKInitialized) {
        // SDK previously initialized. Skip.
        OS_LOG("EOS_Initialize already initialized");
        return true;
    }

    EOS_InitializeOptions SDKOptions = {0};
    SDKOptions.ApiVersion = EOS_INITIALIZE_API_LATEST;
    // TODO: Use the actual product name
    SDKOptions.ProductName = env->GetStringUTFChars(ProductName, nullptr);
    SDKOptions.ProductVersion = env->GetStringUTFChars(ProductVersion, nullptr);
    const char *androidPath = env->GetStringUTFChars(Path, nullptr);
    static EOS_Android_InitializeOptions JNIOptions = {0};
    JNIOptions.ApiVersion = EOS_ANDROID_INITIALIZEOPTIONS_API_LATEST;
    JNIOptions.Reserved = nullptr;
    JNIOptions.OptionalInternalDirectory = androidPath;
    JNIOptions.OptionalExternalDirectory = androidPath;
    SDKOptions.SystemInitializeOptions = &JNIOptions;
    EOS_EResult InitResult = EOS_Initialize(&SDKOptions);
    switch (InitResult) {
        case EOS_EResult::EOS_Android_JavaVMNotStored: {
            OS_LOG("EOS_Android_JavaVMNotStored");
            break;
        }
        case EOS_EResult::EOS_Success:
        case EOS_EResult::EOS_AlreadyConfigured: {
            OS_LOG("Initialization successful");
            IsSDKInitialized = true;
            EOS_Logging_SetCallback(LogMessage);
            EOS_Logging_SetLogLevel(EOS_ELogCategory::EOS_LC_ALL_CATEGORIES, EOS_ELogLevel::EOS_LOG_VeryVerbose);
            break;
        }
        default: {
            OS_LOG_ERROR("EOS_Initialize failed: %s", InitResult);
            break;
        }
    }

    return IsSDKInitialized;
}

void AuthLogin(const EOS_Auth_LoginOptions &options, const EOS_Auth_OnLoginCallback delegate, jobject context) {
    EOS_HAuth handle = EOS_Platform_GetAuthInterface(PlatformHandle);
    LoginInProgress();
    EOS_Auth_Login(handle, &options, context, delegate);
}

/** Attempt a login to the EOS Auth Interface with any previously stored secure credentials (as a result of a previous session calling LoginWithPortalAuth successfully)
 *  If no credential exist then the result EOS_NotFound will be returned to indicate the we still need to login for the first time
 *  If credentials do exist they will be maintained across sessions until we call logout
 *  This should be called after createPlatform and before allowing the user any manual login options */
void LoginPersistentAuth(jobject context) {
    OS_LOG("Performing Persistent login");

    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(PlatformHandle);

    EOS_Auth_Credentials Credentials = {};
    Credentials.ApiVersion = EOS_AUTH_CREDENTIALS_API_LATEST;
    Credentials.Type = EOS_ELoginCredentialType::EOS_LCT_PersistentAuth;
    Credentials.Id = nullptr;
    Credentials.Token = nullptr;

    EOS_Auth_LoginOptions LoginOptions = {0};
    LoginOptions.ApiVersion = EOS_AUTH_LOGIN_API_LATEST;
    LoginOptions.Credentials = &Credentials;
    AuthLogin(LoginOptions, PersistentAuthLoginCb, context);
}

/** Attempt a login to the EOS Auth Interface using the web account portal */
void LoginWithPortalAuth(jobject context) {
    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(PlatformHandle);

    EOS_Auth_Credentials Credentials = {};
    Credentials.ApiVersion = EOS_AUTH_CREDENTIALS_API_LATEST;
    Credentials.Type = EOS_ELoginCredentialType::EOS_LCT_AccountPortal;
    Credentials.Id = nullptr;
    Credentials.Token = nullptr;

    EOS_Auth_LoginOptions LoginOptions = {0};
    LoginOptions.ApiVersion = EOS_AUTH_LOGIN_API_LATEST;
    LoginOptions.Credentials = &Credentials;
    // TODO: Allow the plugin user to set the scope properly
    LoginOptions.ScopeFlags = \
        EOS_EAuthScopeFlags::EOS_AS_BasicProfile | \
        EOS_EAuthScopeFlags::EOS_AS_Country;
    AuthLogin(LoginOptions, AuthLoginCb, context);
}



/** Register for updates that reflect changes in the users login status for the EOS Auth Interface */
void AddNotifyLoginStatusChanged() {
    if (NotifyLoginStatusChangedId != EOS_INVALID_NOTIFICATIONID) {
        return;
    }

    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(PlatformHandle);
    EOS_Auth_AddNotifyLoginStatusChangedOptions LoginStatusChangedOptions = {0};
    LoginStatusChangedOptions.ApiVersion = EOS_AUTH_ADDNOTIFYLOGINSTATUSCHANGED_API_LATEST;
    NotifyLoginStatusChangedId = EOS_Auth_AddNotifyLoginStatusChanged(AuthHandle, &LoginStatusChangedOptions, nullptr,
                                                                      AuthNotifyLoginStatusChangedCb);
}

/** Shutdown the EOS SDK, normally during application termination
 *  This is also the safest way to release any created platforms we are tracking
 *  NOTE: initializeSDK and shutdownSDK must be called on the main thread */
void ShutdownSDK() {
    // Release any data returned to us from GetLoggedInDisplayName
    if (LocalUserInfo != nullptr) {
        EOS_UserInfo_Release(LocalUserInfo);
        LocalUserInfo = nullptr;
    }

    EOS_Platform_Release(PlatformHandle);
    PlatformHandle = nullptr;

    EOS_Shutdown();
}

 extern "C" JNIEXPORT void JNICALL
 Java_com_genvidtech_cordova_eos_CordovaEOS_ShutdownSDK(JNIEnv *env, jobject thiz) {
    ShutdownSDK();
 }

/** Unregister for login status updates for the EOS Auth Interface */
void RemoveNotifyLoginStatusChanged() {
    OS_LOG("RemoveNotifyLoginStatusChanged: Unregister");

    if (NotifyLoginStatusChangedId == EOS_INVALID_NOTIFICATIONID) {
        return;
    }

    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(PlatformHandle);
    EOS_Auth_RemoveNotifyLoginStatusChanged(AuthHandle, NotifyLoginStatusChangedId);
    NotifyLoginStatusChangedId = EOS_INVALID_NOTIFICATIONID;
}

/** Initialize the platform interface using the settings we have obtained from the Developer Portal
 *  This is our hub interface for gaining access to other systems */
extern "C" JNIEXPORT jboolean JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_CreatePlatform(
        JNIEnv *env,
        jobject /* this */, jstring ProductID, jstring SandboxID, jstring DeploymentID, jstring ClientID,
        jstring ClientSecret,
        jboolean IsServer, jint Flags) {
    if (PlatformHandle != nullptr) {
        // Platform previously created. Skip.
        OS_LOG("EOS Platform already created");
    } else {
        EOS_Platform_Options PlatformOptions{0};

        PlatformOptions.ApiVersion = EOS_PLATFORM_OPTIONS_API_LATEST;
        PlatformOptions.ProductId = env->GetStringUTFChars(ProductID, nullptr);
        PlatformOptions.SandboxId = env->GetStringUTFChars(SandboxID, nullptr);
        PlatformOptions.DeploymentId = env->GetStringUTFChars(DeploymentID, nullptr);
        PlatformOptions.ClientCredentials.ClientId = env->GetStringUTFChars(ClientID, nullptr);
        PlatformOptions.ClientCredentials.ClientSecret = env->GetStringUTFChars(ClientSecret, nullptr);
        PlatformOptions.bIsServer = IsServer ? EOS_TRUE : EOS_FALSE;
        PlatformOptions.Flags = Flags;
        double taskTimeout = 10.0;
        PlatformOptions.TaskNetworkTimeoutSeconds = &taskTimeout;

        PlatformHandle = EOS_Platform_Create(&PlatformOptions);
        if (PlatformHandle == nullptr) {
            OS_LOG("EOS Platform creation failed");
            return false;
        }

        OS_LOG("EOS Platform creation successful");
    }

    AddNotifyLoginStatusChanged();
    return true;
}

/** Attempt to login with the persistent credentials, or try the login with portal */
 extern "C" JNIEXPORT void JNICALL
 Java_com_genvidtech_cordova_eos_CordovaEOS_LoginPersistent(
         JNIEnv *env,
         jobject /* this */,
         jobject context) {
    LoginPersistentAuth(LocalENV->NewGlobalRef(context));
}

/** Attempt to login with the persistent credentials, or try the login with portal */
extern "C" JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_LoginWithPortal(
        JNIEnv *env,
        jobject /* this */,
        jobject context
    ) {
   LoginWithPortalAuth(LocalENV->NewGlobalRef(context));
}

/** Attempt to logout of the EOS Auth Interface
 *  If any stored secure credentials exist on the device, they will also be removed */
extern "C" JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_Logout(
        JNIEnv *env,
        jobject /* this */,
        jobject context
    ) {
    EOS_HAuth AuthHandle = EOS_Platform_GetAuthInterface(PlatformHandle);
    EOS_Auth_LogoutOptions LogoutOptions = {0};
    LogoutOptions.ApiVersion = EOS_AUTH_LOGOUT_API_LATEST;
    LogoutOptions.LocalUserId = LocalUserId;
    EOS_Auth_Logout(AuthHandle, &LogoutOptions, LocalENV->NewGlobalRef(context), AuthLogoutCb);
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_IsLoggedIn(JNIEnv *env, jobject thiz) {
    if (PlatformHandle == nullptr) {
        return false;
    }
    if (LocalUserId == nullptr) {
        return false;
    }
    EOS_HAuth hHandle = EOS_Platform_GetAuthInterface(PlatformHandle);
    EOS_ELoginStatus status = EOS_Auth_GetLoginStatus(hHandle, LocalUserId);
    return status == EOS_ELoginStatus::EOS_LS_LoggedIn;
}

/** Tick all active platforms so that they can update and processes any in-flight/incoming HTTP requests or services */
extern "C" JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_Tick(
        JNIEnv *env,
        jobject
        /* this */) {
    EOS_Platform_Tick(PlatformHandle);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_GetVersion(
        JNIEnv *env,
        jobject /* this */) {
    return LocalENV->NewStringUTF(EOS_GetVersion());
}

/** Suspend signals to the SDK that the application status will change to background */
extern "C"
JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_Suspend(JNIEnv *env, jobject thiz) {
    EOS_Platform_SetApplicationStatus(PlatformHandle, EOS_EApplicationStatus::EOS_AS_BackgroundSuspended);
}

/** Resume signals to the SDK that the application status will change to foreground */
extern "C"
JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_Resume(JNIEnv *env, jobject thiz) {
    EOS_Platform_SetApplicationStatus(PlatformHandle, EOS_EApplicationStatus::EOS_AS_Foreground);
}

void UpdateNetwork(EOS_ENetworkStatus status) {
    EOS_Platform_SetNetworkStatus(PlatformHandle, status);
}

extern "C"
JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_NetworkChanged(JNIEnv *env, jobject thiz, jboolean connected) {
    UpdateNetwork(connected ? EOS_ENetworkStatus::EOS_NS_Online : EOS_ENetworkStatus::EOS_NS_Disabled);
}

/** Store reference to CordovaEOS instance */
extern "C"
JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_PassCordovaEOSInstance(JNIEnv *env, jobject thiz) {
    GlobalRefCordovaEOSInstance = LocalENV->NewGlobalRef(thiz);
}

/* EComm section */

JsonValue EosCopyEntitlement(EOS_Ecom_Entitlement* Entitlement) {
    char message[2048] = { '\0' };
    snprintf(message, (sizeof message) - 1, "New Entitlement : %s (%s) : %s",
    Entitlement->EntitlementName,
    Entitlement->EntitlementId,
    Entitlement->bRedeemed ? "redeemed" : "not redeemed");
    OS_LOG(message);
    JsonValue jsEntitlement = JsonValue::MakeObject();
    jsEntitlement.AddProperty("Name", JsonValue::MakeString(Entitlement->EntitlementName));
    jsEntitlement.AddProperty("Id", JsonValue::MakeString(Entitlement->EntitlementId));
    jsEntitlement.AddProperty("CatalogItemId", JsonValue::MakeString(Entitlement->CatalogItemId));
    jsEntitlement.AddProperty("Redeemed", JsonValue::MakeBoolean(Entitlement->bRedeemed == EOS_TRUE));
    jsEntitlement.AddProperty("EndTimestamp", JsonValue::MakeTimestamp(Entitlement->EndTimestamp));
    return std::move(jsEntitlement);
}

void EosQueryEntitlementsCallback(const EOS_Ecom_QueryEntitlementsCallbackInfo* Data) {
    jobject context = (jobject)Data->ClientData;
    jmethodID MethodID = LocalENV->GetMethodID(GlobalRefCordovaEOSClass, "OnQueryEntitlementsResult", "(ZLjava/lang/String;Ljava/lang/Object;)V");
    char message[2048] = {'\0'};
    message[sizeof message - 1] = '\0';
    if (Data->ResultCode != EOS_EResult::EOS_Success) {
        std::snprintf(message, (sizeof message) - 1 , "Query Entitlements error: %s", EOS_EResult_ToString(Data->ResultCode));
        LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, false, LocalENV->NewStringUTF(message), context);
    } else {
        EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(PlatformHandle);
        EOS_Ecom_GetEntitlementsCountOptions options = { 0 };
        options.ApiVersion = EOS_ECOM_GETENTITLEMENTSCOUNT_API_LATEST;
        options.LocalUserId = LocalUserId;
        const uint32_t numOfEntitlements = EOS_Ecom_GetEntitlementsCount(EcomHandle, &options);
        std::snprintf(message, (sizeof message) - 1 , "Ecom Query: Found %d entitlements", numOfEntitlements);
        OS_LOG(message);
        EOS_Ecom_CopyEntitlementByIndexOptions entitlementOptions = { 0 };
        entitlementOptions.ApiVersion = EOS_ECOM_COPYENTITLEMENTBYINDEX_API_LATEST;
        entitlementOptions.LocalUserId = LocalUserId;
        JsonValue jsEntitlements = JsonValue::MakeArray();
        for(int i = 0; i < numOfEntitlements; ++i) {
            EOS_Ecom_Entitlement* entitlement = nullptr;
            entitlementOptions.EntitlementIndex = i;
            const EOS_EResult result = EOS_Ecom_CopyEntitlementByIndex(EcomHandle, &entitlementOptions, &entitlement);
            switch(result) {
                case EOS_EResult::EOS_Success:
                case EOS_EResult::EOS_Ecom_EntitlementStale:
                {
                    jsEntitlements.Append(EosCopyEntitlement(entitlement));
                    EOS_Ecom_Entitlement_Release(entitlement);
                }
                break;
                default:
                {
                    std::snprintf(message, (sizeof message) - 1, "Error retrieving entitlement %i: %s", i, EOS_EResult_ToString(result));
                    OS_LOG(message);
                }
            }
        }
        JsonValue resp = JsonValue::MakeObject();
        resp.AddProperty("entitlements", jsEntitlements);
        LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, true, LocalENV->NewStringUTF(resp.toJson().c_str()), context);
    }
    LocalENV->DeleteGlobalRef(context);
}

const char* EosItemTypeToString(EOS_EEcomItemType type) {
    switch (type) {
        case EOS_EEcomItemType::EOS_EIT_Durable:
            return "Durable";
        case EOS_EEcomItemType::EOS_EIT_Consumable:
            return "Consumable";
        case EOS_EEcomItemType::EOS_EIT_Other:
        default:
            return "Other";
    }
}

JsonValue EosCopyItem(EOS_Ecom_CatalogItem* item) {
    char message[2048] = { '\0' };
    snprintf(message, (sizeof message) - 1, ">> Item %s - %s", item->Id, item->TitleText);
    OS_LOG(message);
    JsonValue jsItem = JsonValue::MakeObject();
    jsItem.AddProperty("Id", JsonValue::MakeString(item->Id));
    jsItem.AddProperty("Title", JsonValue::MakeString(item->TitleText));
    jsItem.AddProperty("Description", JsonValue::MakeString(item->DescriptionText));
    jsItem.AddProperty("LongDescription", JsonValue::MakeString(item->LongDescriptionText));
    jsItem.AddProperty("TechnicalDetails", JsonValue::MakeString(item->TechnicalDetailsText));
    jsItem.AddProperty("Developer", JsonValue::MakeString(item->DeveloperText));
    jsItem.AddProperty("ItemType", JsonValue::MakeString(EosItemTypeToString(item->ItemType)));
    jsItem.AddProperty("EntitlementName", JsonValue::MakeString(item->EntitlementName));
    jsItem.AddProperty("EntitlementEnd", JsonValue::MakeTimestamp(item->EntitlementEndTimestamp));
    return std::move(jsItem);
}

JsonValue EosCopyItems(EOS_HEcom EcomHandle, EOS_Ecom_CatalogOffer* offer) {
    EOS_Ecom_GetOfferItemCountOptions options = { 0 };
    options.ApiVersion = EOS_ECOM_GETOFFERITEMCOUNT_API_LATEST;
    options.LocalUserId = LocalUserId;
    options.OfferId = offer->Id;
    const uint32_t numOfItems = EOS_Ecom_GetOfferItemCount(EcomHandle, &options);
    char message[2048] = { '\0' };
    std::snprintf(message, (sizeof message) - 1 , "Ecom Query: Found %d items in offer %s", numOfItems, offer->Id);
    OS_LOG(message);
    EOS_Ecom_CopyOfferItemByIndexOptions itemOptions = { 0 };
    itemOptions.ApiVersion = EOS_ECOM_COPYOFFERITEMBYINDEX_API_LATEST;
    itemOptions.LocalUserId = LocalUserId;
    itemOptions.OfferId = offer->Id;
    JsonValue jsItems = JsonValue::MakeArray();
    for(int i = 0; i < numOfItems; ++i) {
        EOS_Ecom_CatalogItem* item = nullptr;
        itemOptions.ItemIndex = i;
        const EOS_EResult result = EOS_Ecom_CopyOfferItemByIndex(EcomHandle, &itemOptions, &item);
        if (result != EOS_EResult::EOS_Success) {
            std::snprintf(message, (sizeof message) - 1, "Error retrieving item %d from offer %s: %s", i, offer->Id, EOS_EResult_ToString(result));
            OS_LOG(message);
        } else {
            jsItems.Append(EosCopyItem(item));
            EOS_Ecom_CatalogItem_Release(item);
        }
    }
    return std::move(jsItems);
}

JsonValue EosCopyOffer(EOS_HEcom EcomHandle, EOS_Ecom_CatalogOffer* offer) {
    char message[2048] = { '\0' };
    snprintf(message, (sizeof message) - 1, "> Offer %s - %s", offer->Id, offer->TitleText);
    OS_LOG(message);
    JsonValue jsOffer = JsonValue::MakeObject();
    jsOffer.AddProperty("Id", JsonValue::MakeString(offer->Id));
    jsOffer.AddProperty("Title", JsonValue::MakeString(offer->TitleText));
    jsOffer.AddProperty("Description", JsonValue::MakeString(offer->DescriptionText));
    jsOffer.AddProperty("LongDescription", JsonValue::MakeString(offer->LongDescriptionText));
    jsOffer.AddProperty("Currency", JsonValue::MakeString(offer->CurrencyCode));
    if (offer->PriceResult == EOS_EResult::EOS_Success) {
        jsOffer.AddProperty("Discount", JsonValue::MakeNumber(offer->DiscountPercentage));
        jsOffer.AddProperty("OriginalPrice", JsonValue::MakeNumber(offer->OriginalPrice64));
        jsOffer.AddProperty("CurrentPrice", JsonValue::MakeNumber(offer->CurrentPrice64));
        jsOffer.AddProperty("DecimalPoint", JsonValue::MakeNumber(offer->DecimalPoint));
    } else {
        std::snprintf(message, (sizeof message) - 1, "Error for price of %s: %s", offer->Id, EOS_EResult_ToString(offer->PriceResult));
        OS_LOG(message);
    }
    jsOffer.AddProperty("Available", JsonValue::MakeBoolean(offer->bAvailableForPurchase));
    if (offer->ExpirationTimestamp != EOS_ECOM_CATALOGOFFER_EXPIRATIONTIMESTAMP_UNDEFINED) {
        jsOffer.AddProperty("Expiration", JsonValue::MakeTimestamp(offer->ExpirationTimestamp));
    }
    if (offer->ReleaseDateTimestamp != EOS_ECOM_CATALOGOFFER_RELEASEDATETIMESTAMP_UNDEFINED) {
        jsOffer.AddProperty("ReleaseDate", JsonValue::MakeTimestamp(offer->ReleaseDateTimestamp));
    }
    if (offer->EffectiveDateTimestamp != EOS_ECOM_CATALOGOFFER_EFFECTIVEDATETIMESTAMP_UNDEFINED) {
        jsOffer.AddProperty("EffectiveDate", JsonValue::MakeTimestamp(offer->EffectiveDateTimestamp));
    }

    jsOffer.AddProperty("Items", EosCopyItems(EcomHandle, offer));
    return std::move(jsOffer);
}

void EosQueryOffersCallback(const EOS_Ecom_QueryOffersCallbackInfo* Data) {
    jobject context = (jobject)Data->ClientData;
    jmethodID MethodID = LocalENV->GetMethodID(GlobalRefCordovaEOSClass, "OnQueryOffersResult", "(ZLjava/lang/String;Ljava/lang/Object;)V");
    char message[2048] = {'\0'};
    message[sizeof message - 1] = '\0';
    if (Data->ResultCode != EOS_EResult::EOS_Success) {
        std::snprintf(message, (sizeof message) - 1 , "Query Offer error: %s", EOS_EResult_ToString(Data->ResultCode));
        LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, false, LocalENV->NewStringUTF(message), context);
    } else {
        EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(PlatformHandle);
        EOS_Ecom_GetOfferCountOptions options = { 0 };
        options.ApiVersion = EOS_ECOM_GETOFFERCOUNT_API_LATEST;
        options.LocalUserId = LocalUserId;
        const uint32_t numOfOffers = EOS_Ecom_GetOfferCount(EcomHandle, &options);
        std::snprintf(message, (sizeof message) - 1 , "Ecom Query: Found %d offers", numOfOffers);
        OS_LOG(message);
        EOS_Ecom_CopyOfferByIndexOptions offerOptions = { 0 };
        offerOptions.ApiVersion = EOS_ECOM_COPYOFFERBYINDEX_API_LATEST;
        offerOptions.LocalUserId = LocalUserId;
        JsonValue jsOffers = JsonValue::MakeArray();
        for(int i = 0; i < numOfOffers; ++i) {
            EOS_Ecom_CatalogOffer* offer = nullptr;
            offerOptions.OfferIndex = i;
            const EOS_EResult result = EOS_Ecom_CopyOfferByIndex(EcomHandle, &offerOptions, &offer);
            if (result != EOS_EResult::EOS_Success) {
                std::snprintf(message, (sizeof message) - 1, "Error retrieving offer %i: %s", i, EOS_EResult_ToString(result));
                OS_LOG(message);
            } else {
                jsOffers.Append(EosCopyOffer(EcomHandle, offer));
                EOS_Ecom_CatalogOffer_Release(offer);
            }
        }
        JsonValue resp = JsonValue::MakeObject();
        resp.AddProperty("offers", jsOffers);
        LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, true, LocalENV->NewStringUTF(resp.toJson().c_str()), context);
    }
    LocalENV->DeleteGlobalRef(context);
}

void CheckoutCompleteCallbackFn(const EOS_Ecom_CheckoutCallbackInfo* Data) {
    jobject context = (jobject)Data->ClientData;
    jmethodID MethodID = LocalENV->GetMethodID(GlobalRefCordovaEOSClass, "OnCheckoutResult", "(ZLjava/lang/String;Ljava/lang/Object;)V");
    char message[2048] = {'\0'};
    message[sizeof message - 1] = '\0';
    if (Data->ResultCode != EOS_EResult::EOS_Success) {
        std::snprintf(message, (sizeof message) - 1 , "Checkout error: %s", EOS_EResult_ToString(Data->ResultCode));
        LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, false, LocalENV->NewStringUTF(message), context);
    } else {
        // Some checkout can returned empty;
        JsonValue resp = JsonValue::MakeObject();
        resp.AddProperty("TransactionId", JsonValue::MakeString(Data->TransactionId));
        JsonValue jsEntitlements = JsonValue::MakeArray();
        if (Data->TransactionId) {
            EOS_Ecom_HTransaction TransactionHandle;
            EOS_Ecom_CopyTransactionByIdOptions CopyTransactionOptions{ 0 };
            CopyTransactionOptions.ApiVersion = EOS_ECOM_COPYTRANSACTIONBYID_API_LATEST;
            CopyTransactionOptions.LocalUserId = Data->LocalUserId;
            CopyTransactionOptions.TransactionId = Data->TransactionId;
    
            EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(PlatformHandle);
            auto txnCopyResult = EOS_Ecom_CopyTransactionById(EcomHandle, &CopyTransactionOptions, &TransactionHandle);
            if (txnCopyResult != EOS_EResult::EOS_Success) {
                snprintf(message, (sizeof message)-1, "Error getting transaction '%s': %s", Data->TransactionId, EOS_EResult_ToString(txnCopyResult));
                LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, false, LocalENV->NewStringUTF(message), context);
            } else {
                EOS_Ecom_Transaction_GetEntitlementsCountOptions CountOptions{ 0 };
                CountOptions.ApiVersion = EOS_ECOM_TRANSACTION_GETENTITLEMENTSCOUNT_API_LATEST;
                uint32_t EntitlementCount = EOS_Ecom_Transaction_GetEntitlementsCount(TransactionHandle, &CountOptions);
    
                snprintf(message, (sizeof message)-1, "New entitlements: %d", EntitlementCount);
                OS_LOG(message);
    
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
                        jsEntitlements.Append(EosCopyEntitlement(Entitlement));
                        EOS_Ecom_Entitlement_Release(Entitlement);
                    }
                    break;
                    default:
                    {
                        snprintf(message, (sizeof message) - 1, "Invalid entitlement %d: %s",
                            IndexOptions.EntitlementIndex, EOS_EResult_ToString(CopyResult));
                        OS_LOG(message);
                    }
                    break;
                    }
                }
                EOS_Ecom_Transaction_Release(TransactionHandle);
            }
        }
        resp.AddProperty("NewEntitlements", jsEntitlements);
        LocalENV->CallVoidMethod(GlobalRefCordovaEOSInstance, MethodID, true, LocalENV->NewStringUTF(resp.toJson().c_str()), context);
    }
    LocalENV->DeleteGlobalRef(context);
}

extern "C"
JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_QueryEntitlements(JNIEnv *env, jobject thiz, jobject context) {
    EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(PlatformHandle);
    EOS_Ecom_QueryEntitlementsOptions options = { 0 };
    options.ApiVersion = EOS_ECOM_QUERYENTITLEMENTS_API_LATEST;
    options.LocalUserId = LocalUserId;
    // Query all entitlements
    options.EntitlementNames = nullptr;
    options.EntitlementNameCount = 0;
    // TODO: Make it an option
    options.bIncludeRedeemed = true;
    EOS_Ecom_QueryEntitlements(EcomHandle, &options , LocalENV->NewGlobalRef(context), &EosQueryEntitlementsCallback);
}

extern "C"
JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_QueryOffers(JNIEnv *env, jobject thiz, jobject context) {
    EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(PlatformHandle);
    EOS_Ecom_QueryOffersOptions options = { 0 };
    options.ApiVersion = EOS_ECOM_QUERYOFFERS_API_LATEST;
    options.LocalUserId = LocalUserId;
    EOS_Ecom_QueryOffers(EcomHandle, &options , LocalENV->NewGlobalRef(context), &EosQueryOffersCallback);
}


extern "C"
JNIEXPORT void JNICALL
Java_com_genvidtech_cordova_eos_CordovaEOS_Checkout(JNIEnv *env, jobject thiz, jobjectArray jvOfferIds, jobject context) {
    const jsize length = LocalENV->GetArrayLength(jvOfferIds);
    std::vector<EOS_Ecom_CheckoutEntry> entries;
    std::vector<std::string> ids;
    char message[2048] = {'\0'};
    message[(sizeof message)-1] = '\0';
    for(jsize i = 0; i < length; ++i) {
        const jstring jvOfferId = (jstring)LocalENV->GetObjectArrayElement(jvOfferIds, i);
        const char* utfOfferId = LocalENV->GetStringUTFChars(jvOfferId, nullptr);
        ids.emplace_back(utfOfferId);
        snprintf(message, (sizeof message) - 1, "Checking out offer %s [%d/%d]", utfOfferId, i+1, length);
        OS_LOG(message);
        LocalENV->ReleaseStringUTFChars(jvOfferId, utfOfferId);
        EOS_Ecom_CheckoutEntry entry;
        entry.ApiVersion = EOS_ECOM_CHECKOUTENTRY_API_LATEST;
        entry.OfferId = ids.back().c_str();
        entries.emplace_back(entry);
    }
    EOS_Ecom_CheckoutOptions options = { 0 };
    options.ApiVersion = EOS_ECOM_CHECKOUT_API_LATEST;
    options.LocalUserId = LocalUserId;
    options.EntryCount = length;
    // Note: The entries are copied back internally immediately before the API calls returned.
    options.Entries = entries.data();
    // TODO: Add it as an option
    options.PreferredOrientation = EOS_ECheckoutOrientation::EOS_ECO_Default;
    EOS_HEcom EcomHandle = EOS_Platform_GetEcomInterface(PlatformHandle);
    EOS_Ecom_Checkout(EcomHandle, &options, LocalENV->NewGlobalRef(context), CheckoutCompleteCallbackFn);
}

/** Called by load.library on Java side
    Stores CordovaEOS class for accessing Java methods from JNI */
jint JNI_OnLoad(JavaVM *vm, void *Reserved) {
    if (vm->GetEnv(reinterpret_cast<void **>(&LocalENV), JNI_VERSION_1_6) != JNI_OK) {
        return -1;
    }
    jclass CordovaEOS = LocalENV->FindClass("com/genvidtech/cordova/eos/CordovaEOS");
    GlobalRefCordovaEOSClass = reinterpret_cast<jclass>(LocalENV->NewGlobalRef(CordovaEOS));
    return JNI_VERSION_1_6;
}

void JNI_OnUnload(JavaVM *vm, void *Reserved) {
    RemoveNotifyLoginStatusChanged();
    ShutdownSDK();
    LocalENV->DeleteGlobalRef(GlobalRefCordovaEOSClass);
    LocalENV->DeleteGlobalRef(GlobalRefCordovaEOSInstance);
}