//
//  SQRDataDownloader.m
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2019/1/30.
//  Copyright © 2019 wally.h. All rights reserved.
//

#import "SQRDataDownloader.h"
#import "SQRPlayerItemRemoteCacheTask.h"




@interface SQRDataDownloader () <NSURLSessionDataDelegate>
{
    NSOperationQueue * _kSessionQueue;
    NSURLSession * _kSession;
}
@end

@implementation SQRDataDownloader
+ (instancetype)sharedInstance {
    static SQRDataDownloader * downloader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        downloader = [SQRDataDownloader new];
    });
    return downloader;
}

-(instancetype)init {
    self = [super init];
    if (self) {
        _mapTable = [[NSMapTable alloc] init];
        
        _kSessionQueue = [[NSOperationQueue alloc] init];
        _kSessionQueue.name = @"com.hwh.networkQueue";
        _kSessionQueue.maxConcurrentOperationCount = 5;
        _kSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:_kSessionQueue];
    }
    return self;
}

- (NSURLSession *)session {
    return _kSession;
}

- (void)setObject:(id)anObject forKey:(id)aKey {
    [self.mapTable setObject:anObject forKey:aKey];
}
#pragma mark - url sesson delegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    SQRPlayerItemRemoteCacheTask * operation = [self.mapTable objectForKey:task];
    if ([operation respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        [operation URLSession:session task:task didCompleteWithError:error];
    }
}
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    SQRPlayerItemRemoteCacheTask * operation = [self.mapTable objectForKey:dataTask];
    if ([operation respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
        [operation URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    SQRPlayerItemRemoteCacheTask * operation = [self.mapTable objectForKey:dataTask];
    if ([operation respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        [operation URLSession:session dataTask:dataTask didReceiveData:data];
    }

}

@end
