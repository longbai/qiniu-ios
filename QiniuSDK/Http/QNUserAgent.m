//
//  QNUserAgent.m
//  QiniuSDK
//
//  Created by bailong on 14-9-29.
//  Copyright (c) 2014年 Qiniu. All rights reserved.
//

#import <Foundation/Foundation.h>
#if __IPHONE_OS_VERSION_MIN_REQUIRED
#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>
#else
#import <CoreServices/CoreServices.h>
#endif

#import "QNUserAgent.h"
#import "QNVersion.h"

static NSString *qn_clientId(void) {
#if __IPHONE_OS_VERSION_MIN_REQUIRED
    NSString *s = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (s == nil) {
        s = @"simulator";
    }
    return s;
#else
    long long now_timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
    int r = arc4random() % 1000;
    return [NSString stringWithFormat:@"%lld%u", now_timestamp, r];
#endif
}

static NSString *qn_userAgent(NSString *id) {
#if __IPHONE_OS_VERSION_MIN_REQUIRED
    return [NSString stringWithFormat:@"QiniuObject-C/%@ (%@; iOS %@; %@)", kQiniuVersion, [[UIDevice currentDevice] model], [[UIDevice currentDevice] systemVersion], id];
#else
    return [NSString stringWithFormat:@"QiniuObject-C/%@ (Mac OS X %@; %@)", kQiniuVersion, [[NSProcessInfo processInfo] operatingSystemVersionString], id];
#endif
}

@interface QNUserAgent ()
@property (nonatomic) NSString *ua;
@end

@implementation QNUserAgent

- (NSString *)description {
    return _ua;
}

- (instancetype)init {
    if (self = [super init]) {
        _id = qn_clientId();
        _ua = qn_userAgent(_id);
    }
    return self;
}

/**
 *  UserAgent
 */
-(NSString *)getUserAgent:(NSString *)access{
    
    if (access.length == 0) {
        return access;
    }else{
        NSUInteger index = access.length > 16 ? 16 : access.length;
        NSString *user = [_ua stringByReplacingOccurrencesOfString:@")" withString:@"; "];
        return [NSString stringWithFormat:@"%@%@)",user,[access substringToIndex:index]];
    }
}

/**
 *  单例
 */
+ (instancetype)sharedInstance {
    static QNUserAgent *sharedInstance = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });

    return sharedInstance;
}

@end
