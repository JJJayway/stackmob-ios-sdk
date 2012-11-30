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

#import "SMJSONRequestOperation.h"

@implementation SMJSONRequestOperation

+ (NSSet *)acceptableContentTypes {
    NSSet *defaultAcceptableContentTypes = [super acceptableContentTypes];
    return [defaultAcceptableContentTypes setByAddingObject:@"application/vnd.stackmob+json"];
}

+ (AFJSONRequestOperation *)JSONRequestOperationWithRequest:(NSURLRequest *)urlRequest
                                                    success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success
                                                    failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    // Run callbacks on a private queue. This *should* work, as the context queue should be blocked in -syncWithSemaphore
    
    static dispatch_queue_t private_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        private_queue = dispatch_queue_create("network callback", 0);
    });
    
    AFJSONRequestOperation *requestOperation = [super JSONRequestOperationWithRequest:urlRequest success:success failure:failure];
    
    requestOperation.successCallbackQueue = private_queue;
    requestOperation.failureCallbackQueue = private_queue;
    
    return requestOperation;
}

@end
