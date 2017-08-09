//
//  Created by huanwh on 2017/7/31.

//

#import "SQRPlayerItemRemoteCacheTask.h"
#import "SQRPlayerItemCacheFile.h"
#import "SQRCacheSupportUtils.h"
#import "SQRMediaPlayer.h"


@interface SQRPlayerItemRemoteCacheTask ()<NSURLConnectionDataDelegate>
{
@private
    NSUInteger _offset;
    NSUInteger _requestLength;
    
    NSError *_error;
    
    NSURLConnection *_connection;
    BOOL _dataSaved;
    
    CFRunLoopRef _runloop;
}

@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;
//@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;

@end

@implementation SQRPlayerItemRemoteCacheTask
@synthesize executing = _executing;
@synthesize finished = _finished;
//@synthesize cancelled = _cancelled;

- (void)main
{
    @autoreleasepool
    {
        if ([self isCancelled])
        {
            [self handleFinished];
            return;
        }
        
        [self setFinished:NO];
        [self setExecuting:YES];
        [self startURLRequestWithRequest:_loadingRequest range:_range];
        [self handleFinished];
    }
}

- (void)handleFinished
{
    if (!_loadingRequest) {
        LOG_I(@"远程请求持有请求 被释放",nil);
    }
    if (self.finishBlock && _loadingRequest)
    {
        LOG_I(@"远程请求回调",nil);
        self.finishBlock(self,_error);
    }
    [self setExecuting:NO];
    [self setFinished:YES];
}

- (void)cancel
{
    [super cancel];
    [_connection cancel];
}

- (void)startURLRequestWithRequest:(AVAssetResourceLoadingRequest *)loadingRequest range:(NSRange)range
{
    NSMutableURLRequest *urlRequest = [loadingRequest.request mutableCopy];
    urlRequest.URL = [loadingRequest.request.URL mc_avplayerOriginalURL];
    urlRequest.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    _offset = 0;
    _requestLength = 0;
    if (!(_response && ![_response mc_supportRange]))
    {
        NSString *rangeValue = MCRangeToHTTPRangeHeader(range);
        if (rangeValue)
        {
            [urlRequest setValue:rangeValue forHTTPHeaderField:@"Range"];
            _offset = range.location;
            _requestLength = range.length;
        }
    }
    
    _connection = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self startImmediately:NO];
    [_connection start];
    [self startRunLoop];
}

- (void)synchronizeCacheFileIfNeeded
{
    if (_dataSaved)
    {
        [_cacheFile synchronize];
    }
}

- (void)startRunLoop
{
    _runloop = CFRunLoopGetCurrent();
    CFRunLoopRun();
}

- (void)stopRunLoop
{
    if (_runloop)
    {
        CFRunLoopStop(_runloop);
    }
}

#pragma mark - handle connection
- (nullable NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(nullable NSURLResponse *)response
{
    if (response)
    {
        _loadingRequest.redirect = request;
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if (_response || !response)
    {
        return;
    }
    if ([response isKindOfClass:[NSHTTPURLResponse class]])
    {
        _response = (NSHTTPURLResponse *)response;
        [_cacheFile setResponse:_response];
        [_loadingRequest mc_fillContentInformation:_response];
    }
    if (![_response mc_supportRange])
    {
        _offset = 0;
    }
    if (_offset == NSUIntegerMax)
    {
        _offset = (NSUInteger)_response.mc_fileLength - _requestLength;
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (data.bytes && data.length<=2) {
        _dataSaved = YES;
        _offset += [data length];
        
        [_loadingRequest.dataRequest respondWithData:data];
    }
    else if (data.bytes && [_cacheFile saveData:data atOffset:_offset synchronize:NO])
    {
        _dataSaved = YES;
        _offset += [data length];
        
        [_loadingRequest.dataRequest respondWithData:data];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    LOG_I(@"远程请求完成",nil);

    [self synchronizeCacheFileIfNeeded];
    [self stopRunLoop];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self synchronizeCacheFileIfNeeded];
    _error = error;
    [self stopRunLoop];
}

- (void)setFinished:(BOOL)finished
{
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing
{
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

@end
