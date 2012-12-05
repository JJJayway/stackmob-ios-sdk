/*
 * Copyright 2012 StackMob
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "SMDataStore+Protected.h"
#import "SMError.h"
#import "SMJSONRequestOperation.h"
#import "SMRequestOptions.h"
#import "SMNetworkReachability.h"

@implementation SMDataStore (SpecialCondition)

- (NSError *)errorFromResponse:(NSHTTPURLResponse *)response JSON:(id)JSON
{
    return [NSError errorWithDomain:HTTPErrorDomain code:response.statusCode userInfo:JSON];
}

- (SMFullResponseSuccessBlock)SMFullResponseSuccessBlockForSchema:(NSString *)schema withSuccessBlock:(SMDataStoreSuccessBlock)successBlock
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        if (successBlock) {
            successBlock(JSON, schema);
        }
    };
}

- (SMFullResponseSuccessBlock)SMFullResponseSuccessBlockForObjectId:(NSString *)theObjectId ofSchema:(NSString *)schema withSuccessBlock:(SMDataStoreObjectIdSuccessBlock)successBlock 
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        if (successBlock) {
            successBlock(theObjectId, schema);
        }
    };
}

- (SMFullResponseSuccessBlock)SMFullResponseSuccessBlockForSuccessBlock:(SMSuccessBlock)successBlock 
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        if (successBlock) {
            successBlock();
        }
    };
}

- (SMFullResponseSuccessBlock)SMFullResponseSuccessBlockForResultSuccessBlock:(SMResultSuccessBlock)successBlock 
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        if (successBlock) {
            successBlock(JSON);
        }
    };
}

- (SMFullResponseSuccessBlock)SMFullResponseSuccessBlockForResultsSuccessBlock:(SMResultsSuccessBlock)successBlock 
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        if (successBlock) {
            successBlock(JSON);
        }
    };
}

- (SMFullResponseSuccessBlock)SMFullResponseSuccessBlockForQuerySuccessBlock:(SMResultsSuccessBlock)successBlock
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        if (successBlock) {
            successBlock((NSArray *)JSON);
        }
    };
}


- (SMFullResponseFailureBlock)SMFullResponseFailureBlockForObject:(NSDictionary *)theObject ofSchema:(NSString *)schema withFailureBlock:(SMDataStoreFailureBlock)failureBlock
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON)
    {
        if (failureBlock) {
            response == nil ? failureBlock(error, theObject, schema) : failureBlock([self errorFromResponse:response JSON:JSON], theObject, schema);
        }
    };
}

- (SMFullResponseFailureBlock)SMFullResponseFailureBlockForObjectId:(NSString *)theObjectId ofSchema:(NSString *)schema withFailureBlock:(SMDataStoreObjectIdFailureBlock)failureBlock
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON)
    {
        if (failureBlock) {
            response == nil ? failureBlock(error, theObjectId, schema) : failureBlock([self errorFromResponse:response JSON:JSON], theObjectId, schema);
        }
    };
}

- (SMFullResponseFailureBlock)SMFullResponseFailureBlockForFailureBlock:(SMFailureBlock)failureBlock
{
    return ^void(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON)
    {
        if (failureBlock) {
            response == nil ? failureBlock(error) : failureBlock([self errorFromResponse:response JSON:JSON]);
        }
    };
}

- (int)countFromRangeHeader:(NSString *)rangeHeader results:(NSArray *)results
{
    if (rangeHeader == nil) {
        //No range header means we've got all the results right here (1 or 0)
        return [results count];
    } else {
        NSArray* parts = [rangeHeader componentsSeparatedByString: @"/"];
        if ([parts count] != 2) return -1;
        NSString *lastPart = [parts objectAtIndex: 1];
        if ([lastPart isEqualToString:@"*"]) return -2;
        if ([lastPart isEqualToString:@"0"]) return 0;
        int count = [lastPart intValue];
        if (count == 0) return -1; //real zero was filtered out above
        return count;
    } 
}

- (void)readObjectWithId:(NSString *)theObjectId inSchema:(NSString *)schema parameters:(NSDictionary *)parameters options:(SMRequestOptions *)options onSuccess:(SMDataStoreSuccessBlock)successBlock onFailure:(SMDataStoreObjectIdFailureBlock)failureBlock
{
    if (theObjectId == nil || schema == nil) {
        if (failureBlock) {
            NSError *error = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorInvalidArguments userInfo:nil];
            failureBlock(error, theObjectId, schema);
        }
    } else {
        NSString *path = [[schema lowercaseString] stringByAppendingPathComponent:[self URLEncodedStringFromValue:theObjectId]];
        NSMutableURLRequest *request = [[self.session oauthClientWithHTTPS:options.isSecure] requestWithMethod:@"GET" path:path parameters:parameters];
        SMFullResponseSuccessBlock urlSuccessBlock = [self SMFullResponseSuccessBlockForSchema:schema withSuccessBlock:successBlock];
        SMFullResponseFailureBlock urlFailureBlock = [self SMFullResponseFailureBlockForObjectId:theObjectId ofSchema:schema withFailureBlock:failureBlock];
        [self queueRequest:request options:options onSuccess:urlSuccessBlock onFailure:urlFailureBlock];
    }
}

- (void)refreshAndRetry:(NSURLRequest *)request onSuccess:(SMFullResponseSuccessBlock)onSuccess onFailure:(SMFullResponseFailureBlock)onFailure
{
    if (self.session.refreshing) {
        NSError *error = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorRefreshTokenInProgress userInfo:nil];
        onFailure(request, nil, error, nil);
    } else {
        __block SMRequestOptions *options = [SMRequestOptions options];
        [options setTryRefreshToken:NO];
        [self.session refreshTokenOnSuccess:^(NSDictionary *userObject) {
            [self queueRequest:[self.session signRequest:request] options:options onSuccess:onSuccess onFailure:onFailure];
        } onFailure:^(NSError *theError) {
            [self queueRequest:[self.session signRequest:request] options:options onSuccess:onSuccess onFailure:onFailure];
        }];
    }
}

- (void)queueRequest:(NSURLRequest *)request options:(SMRequestOptions *)options onSuccess:(SMFullResponseSuccessBlock)onSuccess onFailure:(SMFullResponseFailureBlock)onFailure
{
    if (options.headers && [options.headers count] > 0) {
        // Enumerate through options and add them to the request header.
        NSMutableURLRequest *tempRequest = [request mutableCopy];
        [options.headers enumerateKeysAndObjectsUsingBlock:^(id headerField, id headerValue, BOOL *stop) {
            [tempRequest setValue:headerValue forHTTPHeaderField:headerField];
        }];
        request = tempRequest;
        
        // Set the headers dictionary to empty, to prevent unnecessary enumeration during recursion.
        options.headers = [NSDictionary dictionary];
    }
    
    
    
    if (self.session.refreshToken != nil && options.tryRefreshToken && [self.session accessTokenHasExpired]) {
        [self refreshAndRetry:request onSuccess:onSuccess onFailure:onFailure];
    } 
    else {
        SMFullResponseFailureBlock retryBlock = ^(NSURLRequest *originalRequest, NSHTTPURLResponse *response, NSError *error, id JSON) {
            if ([response statusCode] == SMErrorUnauthorized && options.tryRefreshToken) {
                [self refreshAndRetry:originalRequest onSuccess:onSuccess onFailure:onFailure];
            } else if ([response statusCode] == SMErrorServiceUnavailable && options.numberOfRetries > 0) {
                NSString *retryAfter = [[response allHeaderFields] valueForKey:@"Retry-After"];
                if (retryAfter) {
                    [options setNumberOfRetries:(options.numberOfRetries - 1)];
                    double delayInSeconds = [retryAfter doubleValue];
                    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                        if (options.retryBlock) {
                            options.retryBlock(originalRequest, response, error, JSON, options, onSuccess, onFailure);
                        } else {
                            [self queueRequest:[self.session signRequest:originalRequest] options:options onSuccess:onSuccess onFailure:onFailure];
                        }
                    });
                } else {
                    if (onFailure) {
                        onFailure(originalRequest, response, error, JSON);
                    }
                }
            } else if ([error domain] == NSURLErrorDomain && [error code] == -1009) {
                if (onFailure) {
                    NSError *networkNotReachableError = [[NSError alloc] initWithDomain:SMErrorDomain code:SMErrorNetworkNotReachable userInfo:[error userInfo]];
                    onFailure(originalRequest, response, networkNotReachableError, JSON);
                }
            } else {
                if (onFailure) {
                    onFailure(originalRequest, response, error, JSON);
                }
            }
        };
        
        // Run callbacks on a private queue. This *should* work, as the context queue should be blocked in -syncWithSemaphore
        static dispatch_queue_t private_queue;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            private_queue = dispatch_queue_create("SMDataStore network callback", 0);
        });
        
        AFJSONRequestOperation *op = [SMJSONRequestOperation JSONRequestOperationWithRequest:request success:onSuccess failure:retryBlock];
        op.successCallbackQueue = private_queue;
        op.failureCallbackQueue = private_queue;
        
        [[self.session oauthClientWithHTTPS:FALSE] enqueueHTTPRequestOperation:op];
    }
    
}

- (NSString *)URLEncodedStringFromValue:(NSString *)value
{
    static NSString * const kAFCharactersToBeEscaped = @":/.?&=;+!@#$()~[]";
    //static NSString * const kAFCharactersToLeaveUnescaped = @"[]";
    
	return (__bridge_transfer  NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)value, nil, (__bridge CFStringRef)kAFCharactersToBeEscaped, CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
}



@end
