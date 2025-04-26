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

#import <Availability.h>

#import <Cordova/CDV.h>
#import "CordovaEOS.h"

@interface CordovaEOS () {}
@end

@implementation CordovaEOS

- (void)getSDKVersion:(CDVInvokedUrlCommand*)command
{
    NSDictionary*sdkVersion = @{@"sdkVersion": [[self class] sdkVersion]};
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:sdkVersion];

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


+ (NSString*)sdkVersion
{
    return @"1.1.0";
}

@end
