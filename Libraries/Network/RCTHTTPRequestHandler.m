/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTHTTPRequestHandler.h"

#import "RCTNetworking.h"

@interface RCTHTTPRequestHandler () <NSURLSessionDataDelegate>

@end

@implementation RCTHTTPRequestHandler
{
  NSMapTable *_delegates;
  NSURLSession *_session;
}

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

- (void)invalidate
{
  [_session invalidateAndCancel];
  _session = nil;
}

- (BOOL)isValid
{
  // if session == nil and delegates != nil, we've been invalidated
  return _session || !_delegates;
}

#pragma mark - NSURLRequestHandler

- (BOOL)canHandleRequest:(NSURLRequest *)request
{
  static NSSet<NSString *> *schemes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // technically, RCTHTTPRequestHandler can handle file:// as well,
    // but it's less efficient than using RCTFileRequestHandler
    schemes = [[NSSet alloc] initWithObjects:@"http", @"https", nil];
  });
  return [schemes containsObject:request.URL.scheme.lowercaseString];
}

- (NSURLSessionDataTask *)sendRequest:(NSURLRequest *)request
                         withDelegate:(id<RCTURLRequestDelegate>)delegate
{
  // Lazy setup
  if (!_session && [self isValid]) {

    NSOperationQueue *callbackQueue = [NSOperationQueue new];
    callbackQueue.maxConcurrentOperationCount = 1;
    callbackQueue.underlyingQueue = [[_bridge networking] methodQueue];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    _session = [NSURLSession sessionWithConfiguration:configuration
                                             delegate:self
                                        delegateQueue:callbackQueue];

    _delegates = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory
                                           valueOptions:NSPointerFunctionsStrongMemory
                                               capacity:0];
  }

  NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
  [_delegates setObject:delegate forKey:task];
  [task resume];
  return task;
}

- (void)cancelRequest:(NSURLSessionDataTask *)task
{
  [task cancel];
  [_delegates removeObjectForKey:task];
}

#pragma mark - NSURLSession delegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
  [[_delegates objectForKey:task] URLRequest:task didSendDataWithProgress:totalBytesSent];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
  [[_delegates objectForKey:task] URLRequest:task didReceiveResponse:response];
  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data
{
  [[_delegates objectForKey:task] URLRequest:task didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
  [[_delegates objectForKey:task] URLRequest:task didCompleteWithError:error];
  [_delegates removeObjectForKey:task];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
  // Validate properties
  // - make sure host is going to avatars.curseapp.net
  // - all other redirects should go through standard redirect process
  if (
      session &&
      task &&
      response &&
      response.URL &&
      [[response.URL host] isEqualToString:@"avatars.curseapp.net"]
  ) {
    // Create new task to retrieve the redirected data
    NSURLSessionDataTask *redirectTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable iResponse, NSError * _Nullable error) {
      // Validate all properties
      if (
          iResponse &&
          [iResponse URL] &&
          data &&
          [data length] &&
          request &&
          [request URL] &&
          response &&
          [response URL] &&
          session &&
          task
      ) {
        // Cache the inner response to the original URL
        // - we don't cache the second request's response since that should be cached before entering this block
        NSCachedURLResponse *cacheResponse = [[NSCachedURLResponse alloc] initWithResponse:iResponse data:data];
        if (cacheResponse) {
            [[NSURLCache sharedURLCache] storeCachedResponse:cacheResponse forRequest:[[NSURLRequest alloc] initWithURL:response.URL]];
        }
      }
      
      // Call the completion handler, since the ImageView requires the normal path to complete
      if (completionHandler) {
        completionHandler(request);
      }
    }];
    
    // Start the new task
    [redirectTask resume];
    return;
  }
  
  // If the original request was not to avatars.curseapp.net, pass through the new request
  if (completionHandler) {
    completionHandler(request);
  }
}

@end
