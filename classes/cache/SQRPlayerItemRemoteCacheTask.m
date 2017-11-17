 //
//  Created by huanwh on 2017/7/31.

//

#import "SQRPlayerItemRemoteCacheTask.h"
#import "SQRPlayerItemCacheFile.h"
#import "SQRCacheSupportUtils.h"
#import "SQRMediaPlayer.h"
#import "SQRPlayerHandlerFactory.h"

/**
 * 音频网络 所使用线程管理，以防线程被释放而无法正确回调
 */
@implementation SQRPlayer (Thead)

/// 音频网络下载所在线程
static NSThread * _playerDownloadThread = nil;
/// 音频网络下载所在线程 状态
static bool SQRPlayerThreadActive = false;

+ (void)networkRequestTheadEntryPoint:(BOOL)__unused active {
    @autoreleasepool {
        [[NSThread currentThread] setName:@"com.hwh.player.cacheloaderThead"];
        
        NSRunLoop * runloop = [NSRunLoop currentRunLoop];
//        [runloop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
//        [runloop run];
        while (SQRPlayerThreadActive && [runloop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
    }
}

+ (void)stopNetworkRequestThead:(id)__unused obj {
    @autoreleasepool {
        SQRPlayerThreadActive = false;
        /*
        NSRunLoop * runloop = [NSRunLoop currentRunLoop];
        CFRunLoopRef curRunloop = runloop.getCFRunLoop;
        CFRunLoopStop(curRunloop);
         */
    }
}
/**
 创建网络请求时所在线程
 
 @return 网络请求所在线程
 */
+ (NSThread *)connectThead {
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SQRPlayerThreadActive = true;
        
        _playerDownloadThread = [[NSThread alloc] initWithTarget:self.class selector:@selector(networkRequestTheadEntryPoint:) object:nil];
        [_playerDownloadThread start];
    });
    return _playerDownloadThread;
}

@end

@interface SQRPlayerItemRemoteCacheTask ()<NSURLConnectionDataDelegate>
{
@private
    NSUInteger _offset;
    NSUInteger _requestLength;
    
    NSError *_error;
    
    NSURLConnection *_connection;
    BOOL _dataSaved;
    
    CFRunLoopRef _runloop;
    
    NSUInteger retryCount;
    NSUInteger retryInterval; // 失败后五秒后重试，一次递增5s,尝试retryCount 次
}

@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;
@property (weak,   nonatomic) NSThread * curThread;
@end

@implementation SQRPlayerItemRemoteCacheTask
@synthesize executing = _executing;
@synthesize finished = _finished;

- (instancetype)initWithCacheFile:(SQRPlayerItemCacheFile *)cacheFile loadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest range:(NSRange)range {
    self = [super initWithCacheFile:cacheFile loadingRequest:loadingRequest range:range];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(suspended:) name:SQRCancelOrResumeAllRequestNotification object:nil];
        retryCount = 5;
        retryInterval = 5;
        
        _offset = 0;
    }
    return self;
}


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
            [self startURLRequestWithRequest:self.loadingRequest range:_range];
        }else {
            [self handleFinished];
        }
    }
}

-(void)dealloc {
    LOG_I(@"释放 SQRPlayerItemRemoteCacheTask",nil);
    [_connection cancel];
    [self stopRunLoop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)suspended:(NSNotification *)notification {
    if ([self isCancelled]) {
        [self handleFinished];
        return;
    }
    
    NSDictionary * userinfo = notification.userInfo;
    BOOL canced = [userinfo[@"cancel"] boolValue];
    if (canced) {
        [_connection cancel];
    }else {
        if ([self allowAccessNetwork] && retryCount <= 0) {
            NSAssert(_runloop == CFRunLoopGetCurrent(), @"之前线程和当前不一致");
            retryCount = 5;
            NSRange newRange = NSMakeRange(_offset, NSMaxRange(_range) - _offset);
            [self startURLRequestWithRequest:self.loadingRequest range:newRange];
        }
    }
}

- (void)handleFinished
{
    [self _setNetworkActive:NO];

    if (_connection) {
        [_connection cancel];
    }
    
    if (!self.loadingRequest) {
        LOG_I(@"远程任务 loadingRequest 已释放",nil);
    }
    if (self.finishBlock && self.loadingRequest)
    {
        LOG_I(@"远程任务已完成",nil);
        self.finishBlock(self,_error);
    }
    
    [self stopRunLoop];
    
    [self setExecuting:NO];
    [self setFinished:YES];
}

- (void)startURLRequestWithRequest:(AVAssetResourceLoadingRequest *)loadingRequest range:(NSRange)range
{
    if (_connection) {
        [_connection cancel];
        _connection = nil;
    }
    
    LOG_E(@"网络请求剩余次数 %d",(int)retryCount);
    retryCount--;
    _error = nil;
    
    NSMutableURLRequest *urlRequest = [loadingRequest.request mutableCopy];
    urlRequest.URL = [loadingRequest.request.URL mc_avplayerOriginalURL];
    urlRequest.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    urlRequest.timeoutInterval = 30;
    
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
    
    [self performSelector:@selector(_startWithRequest:) onThread:[SQRPlayer connectThead] withObject:urlRequest waitUntilDone:NO];
    [self startRunLoop];
}

- (void)_startWithRequest:(NSURLRequest *)request {
    if (![request isKindOfClass:[NSURLRequest class]]) {
        LOG_E(@"传入请求错误",nil);
        return;
    }
    _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [_connection start];
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
    
    return;
    
    NSAssert(_runloop == CFRunLoopGetCurrent(), @"之前线程和当前不一致");

    if (_runloop) {
        return;
    }
    
    _curThread = [NSThread currentThread];
    _runloop = CFRunLoopGetCurrent();
    CFRunLoopRun();
}

- (void)stopRunLoop
{
    return;
    
    NSAssert(_runloop == CFRunLoopGetCurrent(), @"之前线程和当前不一致");
    
    if (_runloop && _curThread)
    {
        NSAssert(_curThread, @"当前线程已不存在");
        CFRunLoopStop(_runloop);
        _runloop = nil;
    }
}

-(void)sqr_cancel {
    [_connection cancel];
    [self stopRunLoop];
}
#pragma mark - network state

-(BOOL)allowAccessNetwork {
    id<SQRPlayerNetworkChangedProtocol>handler = [SQRPlayerHandlerFactory hanlerForProtocol:@protocol(SQRPlayerNetworkChangedProtocol)];
    if ([handler respondsToSelector:@selector(mediaPlayerCanUseNetwork:)]) {
        BOOL allowd = [handler mediaPlayerCanUseNetwork:[self.loadingRequest.request.URL mc_avplayerOriginalURL]];
        if (!allowd) {
            _error = sqr_errorWithCode(KMediaPlayerErrorCodeNotAllowNetwork, @"not allowd access network!");
            return NO;
        }
    }
    return YES;
}


- (void)_setNetworkActive:(BOOL)isActive {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:isActive];
    });
}

#pragma mark - handle connection
- (nullable NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(nullable NSURLResponse *)response
{
    [self _setNetworkActive:YES];


    if (response)
    {
        self.loadingRequest.redirect = request;
    }
    return request;
}

/** text/plain
 text/html
 image/jpeg
 image/png
 audio/mpeg
 audio/ogg
 audio/..
 video/mp4
 application/octet-stream
 …
 */
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if ([self isCancelled]) {
        [self handleFinished];
        return;
    }
    
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
        NSString * mimeTeyp = [httpResponse MIMEType];
        NSArray * types = [mimeTeyp componentsSeparatedByString:@"/"];
        NSString * type = nil;
        if (types.count) {
            type = (NSString *)types.firstObject;
            if (![type isEqualToString:@"audio"] && ![type isEqualToString:@"video"]) {
                _error = sqr_errorWithCode(KMediaPlayerErrorCodeResourceTypeError, @"response type is not audio or video");
                LOG_E(@"response type is error. %@",_error);
                [self handleFinished];
                return;
            }
        }
    }
    if (_response || !response)
    {
        return;
    }
    if ([response isKindOfClass:[NSHTTPURLResponse class]])
    {
        _response = (NSHTTPURLResponse *)response;
        [_cacheFile setResponse:_response];
        [self.loadingRequest mc_fillContentInformation:_response];
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
    if ([self isCancelled]) {
        [self handleFinished];
        return;
    }
    if (data.bytes && [_cacheFile saveData:data atOffset:_offset synchronize:NO])
    {
        _dataSaved = YES;
        _offset += [data length];
        [self.loadingRequest.dataRequest respondWithData:data];
    }
    
    retryCount = 5; //重置重试次数
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    LOG_I(@"远程任务完成: %@",NSStringFromRange(_range));

    [self synchronizeCacheFileIfNeeded];
    
    [self _setNetworkActive:NO];
    [self handleFinished];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    if ([self isCancelled]) {
        [self handleFinished];
        return;
    }
    if (retryCount>0 && [self allowAccessNetwork]) {
        sleep((int)retryInterval);
        [self synchronizeCacheFileIfNeeded];
        NSRange newRange = NSMakeRange(_offset, NSMaxRange(_range) - _offset);
        [self startURLRequestWithRequest:self.loadingRequest range:newRange];
        return;
    }
    
    [self synchronizeCacheFileIfNeeded];
    _error = error;
    
    [self _setNetworkActive:NO];
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
