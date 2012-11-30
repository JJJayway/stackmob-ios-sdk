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

#import "Synchronization.h"

void synchronousQuery(SMDataStore *sm, SMQuery *query, SynchronousQuerySuccessBlock successBlock, SynchronousQueryFailureBlock failureBlock) {    
    syncWithSemaphore(^(dispatch_semaphore_t semaphore) {
        [sm performQuery:query onSuccess:^(NSArray *results) {
            successBlock(results);
            syncReturn(semaphore);
        } onFailure:^(NSError *error) {
            failureBlock(error);
            syncReturn(semaphore);
        }];
    });
}

void syncWithSemaphore(void (^block)(dispatch_semaphore_t semaphore)) {
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    block(s);
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER); // Block the MOC private queue, scheduling network callbacks on a private queue (defined in SMJSONRequestOperation.m)
    dispatch_release(s);
}

void syncReturn(dispatch_semaphore_t semaphore) {
    dispatch_semaphore_signal(semaphore);
}
