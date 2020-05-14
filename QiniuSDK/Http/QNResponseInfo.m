//
//  QNResponseInfo.m
//  QiniuSDK
//
//  Created by bailong on 14/10/2.
//  Copyright (c) 2014年 Qiniu. All rights reserved.
//

#import "QNResponseInfo.h"
#import "QNUserAgent.h"
#import "QNVersion.h"

const int kQNZeroDataSize = -6;
const int kQNInvalidToken = -5;
const int kQNFileError = -4;
const int kQNInvalidArgument = -3;
const int kQNRequestCancelled = -2;
const int kQNNetworkError = -1;

static NSString *kQNErrorDomain = @"qiniu.com";

@interface QNResponseInfo ()

@property (assign) int statusCode;
@property (nonatomic, copy) NSString *msg;
@property (nonatomic, copy) NSString *msgDetail;
@property (nonatomic, copy) NSString *reqId;
@property (nonatomic, copy) NSString *xlog;
@property (nonatomic, copy) NSString *xvia;
@property (nonatomic, copy) NSError *error;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *id;
@property (assign) UInt64 timeStamp;

@end

@implementation QNResponseInfo

+ (instancetype)cancelResponse {
    return [QNResponseInfo errorResponseInfo:QNResponseInfoErrorTypeUserCanceled
                                   errorDesc:@"cancelled by user"];
}

+ (instancetype)responseInfoWithNetworkError:(NSString *)desc{
    return [QNResponseInfo errorResponseInfo:QNResponseInfoErrorTypeNetworkError
                                   errorDesc:desc];
}

+ (instancetype)responseInfoWithInvalidArgument:(NSString *)desc{
    return [QNResponseInfo errorResponseInfo:QNResponseInfoErrorTypeInvalidArgs
                                   errorDesc:desc];
}

+ (instancetype)responseInfoWithInvalidToken:(NSString *)desc {
    return [QNResponseInfo errorResponseInfo:QNResponseInfoErrorTypeInvalidToken
                                   errorDesc:desc];
}

+ (instancetype)responseInfoWithFileError:(NSError *)error {
    return [QNResponseInfo errorResponseInfo:QNResponseInfoErrorTypeInvalidFile
                                   errorDesc:nil
                                       error:error];
}

+ (instancetype)responseInfoOfZeroData:(NSString *)path {
    NSString *desc;
    if (path == nil) {
        desc = @"data size is 0";
    } else {
        desc = [[NSString alloc] initWithFormat:@"file %@ size is 0", path];
    }
    return [QNResponseInfo errorResponseInfo:QNResponseInfoErrorTypeZeroSizeFile
                                   errorDesc:desc];
}

+ (instancetype)errorResponseInfo:(QNResponseInfoErrorType)errorType
                        errorDesc:(NSString *)errorDesc{
    return [self errorResponseInfo:errorType errorDesc:errorDesc error:nil];
}

+ (instancetype)errorResponseInfo:(QNResponseInfoErrorType)errorType
                        errorDesc:(NSString *)errorDesc
                            error:(NSError *)error{
    QNResponseInfo *response = [[QNResponseInfo alloc] init];
    response.statusCode = errorType;
    response.msgDetail = errorDesc;
    response.requestMetrics = [QNUploadSingleRequestMetrics emptyMetrics];
    if (error) {
       response.error = error;
    } else {
        NSError *error = [[NSError alloc] initWithDomain:kQNErrorDomain
                                                    code:errorType
                                                userInfo:@{ @"error" : response.msgDetail ?: response.msg ?: @"error" }];
        response.error = error;
    }
    
    return response;
}

- (instancetype)initWithResponseInfoHost:(NSString *)host
                                response:(NSHTTPURLResponse *)response
                                    body:(NSData *)body
                                   error:(NSError *)error {
    
    self = [super init];
    if (self) {
        
        _host = host;
        _timeStamp = [[NSDate date] timeIntervalSince1970];
        _requestMetrics = [QNUploadSingleRequestMetrics emptyMetrics];
        
        if (response) {
            
            int statusCode = (int)[response statusCode];
            NSDictionary *headers = [response allHeaderFields];
            _statusCode = statusCode;
            _reqId = headers[@"X-Reqid"];
            _xlog = headers[@"X-Log"];
            _xvia = !headers[@"X-Via"] ? (!headers[@"X-Px"] ? headers[@"Fw-Via"] : headers[@"X-Px"]) : headers[@"X-Via"];

            if (error) {
                _error = error;
                _statusCode = (int)error.code;
                _message = [NSString stringWithFormat:@"%@", error];
                _responseDictionary = nil;
            } else {
                NSMutableDictionary *errorUserInfo = [@{@"errorHost" : host ?: @""} mutableCopy];
                if (!body) {
                    _message = @"no response data";
                    [errorUserInfo setDictionary:@{@"error":_message}];
                    _error = [[NSError alloc] initWithDomain:kQNErrorDomain code:statusCode userInfo:errorUserInfo];
                    _responseDictionary = nil;
                } else {
                    NSError *tmp = nil;
                    NSDictionary *responseInfo = nil;
                    responseInfo = [NSJSONSerialization JSONObjectWithData:body options:NSJSONReadingMutableLeaves error:&tmp];
                    if (tmp){
                        _message = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] ?: @"";
                        [errorUserInfo setDictionary:@{@"error" : _message}];
                        _error = [[NSError alloc] initWithDomain:kQNErrorDomain code:statusCode userInfo:errorUserInfo];
                        _responseDictionary = nil;
                    } else if (responseInfo && statusCode > 199 && statusCode < 300) {
                        _error = nil;
                        _message = @"ok";
                        _responseDictionary = responseInfo;
                    } else {
                        _message = @"unkown error";
                        [errorUserInfo setDictionary:@{@"error" : _message}];
                        _error = [[NSError alloc] initWithDomain:kQNErrorDomain code:statusCode userInfo:errorUserInfo];
                        _responseDictionary = responseInfo;
                    }
                }
            }
        } else if (error) {
            _error = error;
            _statusCode = (int)error.code;
            _message = [NSString stringWithFormat:@"%@", error];
            _responseDictionary = nil;
        }
    }
    return self;
}

- (BOOL)isCancelled {
    return _statusCode == kQNRequestCancelled || _statusCode == -999;
}

- (BOOL)isNotQiniu {
    // reqId is nill means the server is not qiniu
    return (_statusCode >= 200 && _statusCode < 500) && _reqId == nil;
}

- (BOOL)isOK {
    return (_statusCode >= 200 && _statusCode < 300) && _error == nil && _reqId != nil;
}

- (BOOL)couldRetry {
    if (self.isCancelled
        || (_statusCode > 300 && _statusCode < 400)
        || (_statusCode > 400 && _statusCode < 500)
        || _statusCode == 501 || _statusCode == 573
        || _statusCode == 608 || _statusCode == 612 || _statusCode == 614 || _statusCode == 616
        || _statusCode == 619 || _statusCode == 630 || _statusCode == 631 || _statusCode == 640
        || _statusCode == 701
        ||(_statusCode < 0 && _statusCode > -1000)) {
        return NO;
    } else {
        return YES;
    }
//    return (_statusCode >= 500 && _statusCode < 600 && _statusCode != 579) || _statusCode == 996 || _statusCode == 406 || (_statusCode == 200 && _error != nil) || _statusCode < -1000 || self.isNotQiniu;
}

- (BOOL)couldRegionRetry{
    if ([self couldRetry] == NO
        || _statusCode == 400
        || _statusCode == 502 || _statusCode == 503 || _statusCode == 504 || _statusCode == 579 || _statusCode == 599
        || self.isCancelled) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)couldHostRetry{
    if ([self couldRegionRetry] == NO
        || (_statusCode == 502 || _statusCode == 503 || _statusCode == 571)) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)isConnectionBroken {
    return _statusCode == kQNNetworkError || (_statusCode < -1000 && _statusCode != -1003);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@= id: %@, ver: %@, status: %d, requestId: %@, xlog: %@, xvia: %@, host: %@ time: %llu error: %@>", NSStringFromClass([self class]), _id, kQiniuVersion, _statusCode, _reqId, _xlog, _xvia, _host, _timeStamp, _error];
}

@end
