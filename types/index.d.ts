// Type definitions for cordova-plugin-eos
// Project: https://github.com/genvid-holdings/cordova-plugin-eos
// Definitions by: Microsoft Open Technologies Inc <http://msopentech.com>
//                 Tim Brust <https://github.com/timbru31>
// Definitions: https://github.com/DefinitelyTyped/DefinitelyTyped

/**
 * This plugin exposed some EOS services, including Platform, Authentication and EComm.
 */

interface EosItem {
    Id: string;
    Title: string;
    Description: string;
    LongDescription: string;
    TechnicalDetails: string;
    Developer: string;
    ItemType: "Durable" | "Consumable" | "Other";
    EntitlementName: string;
    EntitlementEnd: string;
}

interface EosOffer {
    Id: string;
    Title: string;
    Description: string;
    LongDescription: string;
    Currency: string;
    Discount?: number;
    OriginalPrice?: number;
    CurrentPrice?: number;
    DecimalPoint?: number;
    Available: boolean;
    Expiration?: string; // ISO8601 date
    ReleaseDate?: string; // ISO8601 date
    EffectiveDate?: string; // ISO8601 date
    Items: Array<EosItem>;
}

interface EosEntitlement {
    Name: string;
    Id: string;
    CatalogItemId: string;
    Redeemed: boolean;
    EndTimestamp?: string;
}

interface EosTransaction {
    TransactionId?: string;
    NewEntitlements: Array<EosEntitlement>;
}

interface EosEcom {
    queryEntitlements(): Promise<Array<EosEntitlement>>;
    queryOffers(): Promise<Array<EosOffer>>;
    checkout(offerIds: string[]): Promise<EosTransaction>;
}

interface EOSLoginStatus {
    status: "loggedIn" | "loggedOut" | "inProgress";
}

interface Log {
    message: string;
}

type onLoginChanged = (status: EOSLoginStatus) => void;
type onLog = (log: Log) => void;

interface EosAuth {
    isLoggedIn(): Promise<boolean>;
    getUsername(): Promise<string>;
    getAccountId(): Promise<string>;
    getAuthToken(): Promise<string>;
    login(persistent: boolean): Promise<boolean>;
    logout(): Promise<boolean>;
}

type EOSSDKConfig = {
    ProductName: string;
    ProductVersion: string;
    ProductId: string;
    SandboxId: string;
    DeploymentId: string;
    ClientId: string; // Must match the one passed to the build
    ClientSecret: string;
}

interface EOS {
    /** Indicates that Cordova initialize successfully. */
    available: boolean;
    initialized: boolean;
    sdkVersion?: string;
    /** Get the EOS SDK version. */
    initializeSDK(config: EOSSDKConfig, handler: onLoginChanged): Promise<void>;
    onConnect(): Promise<void>;
    onDisconnect(): Promise<void>;
    onLog(handler: onLog): Promise<void>;
    auth: EosAuth;
    ecom: EosEcom;
}

declare var plugins: {
    eos: EOS;
};
