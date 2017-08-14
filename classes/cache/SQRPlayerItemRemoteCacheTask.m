 //
//  Created by huanwh on 2017/7/31.

//

#import "SQRPlayerItemRemoteCacheTask.h"
#import "SQRPlayerItemCacheFile.h"
#import "SQRCacheSupportUtils.h"
#import "SQRMediaPlayer.h"
#import "SQRPlayerHandlerFactory.h"


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

@end

@implementation SQRPlayerItemRemoteCacheTask
@synthesize executing = _executing;
@synthesize finished = _finished;

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
        if ([self allowAccessNetwork]) {
            [self startURLRequestWithRequest:_loadingRequest range:_range];
        }
        [self handleFinished];
    }
}

- (void)handleFinished
{
    if (!_loadingRequest) {
        LOG_I(@"remote loadingRequest = nil",nil);
    }
    if (self.finishBlock && _loadingRequest)
    {
        LOG_I(@"remote task finish ",nil);
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
    urlRequest.timeoutInterval = 20;
    
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
#pragma mark - network state

-(BOOL)allowAccessNetwork {
    id<SQRPlayerNetworkChangedProtocol>handler = [SQRPlayerHandlerFactory hanlerForProtocol:@protocol(SQRPlayerNetworkChangedProtocol)];
    if ([handler respondsToSelector:@selector(mediaPlayerCanUseNetwork:)]) {
        BOOL allowd = [handler mediaPlayerCanUseNetwork:[_loadingRequest.request.URL mc_avplayerOriginalURL]];
        if (!allowd) {
            _error = sqr_errorWithCode(KMediaPlayerErrorCodeNotAllowNetwork, @"not allowd access network!");
            return NO;
        }
    }
    return YES;
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
    LOG_I(@"remote request finish",nil);

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
