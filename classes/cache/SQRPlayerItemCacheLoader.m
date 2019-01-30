
//  Created by huanwh on 2017/7/31.


/**
 * 控制加载缓存时所在 队列为 唯一队列
 * no define 则 每次播放器发送请求时都会创建单独的队列处理请求
 */
#define SingleQueue

#import "SQRPlayerItemCacheLoader.h"
#import "SQRPlayerItemLocalCacheTask.h"
#import "SQRPlayerItemRemoteCacheTask.h"
#import "SQRCacheSupportUtils.h"
#import "SQRPlayerItemCacheFile.h"
#import "SQRCacheSupportUtils.h"
#import "SQRMediaPlayer.h"

@interface SQRPlayerItemCacheLoader ()<NSURLConnectionDataDelegate>
{
@private
    NSMutableArray<AVAssetResourceLoadingRequest *> *_pendingRequests;
    AVAssetResourceLoadingRequest *_currentRequest;
    NSRange _currentDataRange;
    NSHTTPURLResponse *_response;
}
@property (nonatomic,strong) NSMutableDictionary * queues;
@property (atomic   ,strong) SQRPlayerItemCacheFile *cacheFile;
#ifdef SingleQueue
@property (nonatomic,strong) NSOperationQueue *singleQueue;
#endif
@end

@implementation SQRPlayerItemCacheLoader

#pragma mark - create load cache thread



#pragma mark - init & dealloc

+ (instancetype)cacheLoaderWithCacheFilePath:(NSString *)cacheFilePath
{
    return [[self alloc] initWithCacheFilePath:cacheFilePath];
}

- (instancetype)initWithCacheFilePath:(NSString *)cacheFilePath
{
    self = [super init];
    if (self)
    {
        self.cacheFile = [SQRPlayerItemCacheFile cacheFileWithFilePath:cacheFilePath];
        if (!self.cacheFile)
        {
            return nil;
        }
        
        _queues          = [NSMutableDictionary dictionary];
        _pendingRequests = [[NSMutableArray alloc] init];
        _currentDataRange = MCInvalidRange;
        
#ifdef SingleQueue
        _singleQueue = [[NSOperationQueue alloc] init];
        _singleQueue.name = @"singleQueue";
        _singleQueue.maxConcurrentOperationCount = 5;
#endif
    }
    return self;
}

- (void)dealloc
{
    // queue
    [self cancelAllQueue];
    _queues = nil;
}

- (void)clear {
    [self cancelAllQueue];
}

- (NSString *)cacheFilePath
{
    return self.cacheFile.cacheFilePath;
}

+ (void)removeCacheWithCacheFilePath:(NSString *)cacheFilePath
{
    [[NSFileManager defaultManager] removeItemAtPath:cacheFilePath error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[cacheFilePath stringByAppendingString:[SQRPlayerItemCacheFile indexFileExtension]] error:NULL];
}

+ (NSError *)removeExpireFiles:(NSInteger)maxFileCount beforeTime:(NSInteger)seconds {
    NSString * dirPath = MCCacheTemporaryDirectory();
    NSDirectoryEnumerator * fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:dirPath];
    
    NSMutableDictionary * validFiles = [NSMutableDictionary dictionary];
    NSError * lastError = nil;
    for (NSString * fileName in fileEnumerator) {
        NSString * filePath = [dirPath stringByAppendingPathComponent:fileName];
        
        NSError * error = nil;
        NSDictionary * attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
        if (error) {
            LOG_I(@"get file attribuation error . %@",error);
            lastError = error;
            break;
        }
        
        NSDate * lastModifyDate = [attrs objectForKey:NSFileModificationDate];
        NSDate * oneDayAge      = [NSDate dateWithTimeIntervalSinceNow:-seconds];
        
        error = nil;
        // 过期文件
        if (lastModifyDate && [lastModifyDate compare:oneDayAge] == NSOrderedAscending) {
            // 移除  文件 & idx （成对删除）
            [[self class] removeCacheWithCacheFilePath:filePath];
        }else {
            // 过滤 idx 文件
            if (![fileName containsString:[SQRPlayerItemCacheFile indexFileExtension]]) {
                NSString * key = [NSString stringWithFormat:@"%f%@",lastModifyDate.timeIntervalSince1970,fileName];
                [validFiles setObject:filePath forKey:key];
            }
        }
        
        error = nil;
    }
    
    if (maxFileCount>0 && validFiles.count > maxFileCount) {
        NSError * error = nil;

        NSArray * filterKeys = [validFiles.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSDate *  _Nonnull obj1, NSDate *  _Nonnull obj2) {
            return [obj1 compare:obj2];
        }];
        
        NSMutableArray * removeKeys = [NSMutableArray arrayWithArray:filterKeys];
        int i = (int)filterKeys.count - (int)maxFileCount;
        while (i > 0) {
            NSString * earlyPath = [validFiles objectForKey:removeKeys.firstObject];
            [[self class] removeCacheWithCacheFilePath:earlyPath];
            [removeKeys removeObject:removeKeys.firstObject];
            
            LOG_I(@"remove caching file at path: \n%@\n",earlyPath);
            i--;
        }
        error = nil;
    }
    
    return lastError;
}

+ (NSError *)removeAllAudioCache {
    NSString * dirPath = MCCacheTemporaryDirectory();
    
    NSError * error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:dirPath error:&error];
    if (error) {
        LOG_E(@"remove audio cache dir failed",nil);
    }
    return error;
}

#pragma mark - loading request
- (void)startNextRequest
{
    if (_pendingRequests.count == 0)
    {
        return;
    }
    
    _currentRequest = [_pendingRequests lastObject];
    
    LOG_I(@"播放器  %lld -  %ld", _currentRequest.dataRequest.requestedOffset,_currentRequest.dataRequest.requestedLength);
    
    // 去除设置最大值，从网络获取的逻辑
    _currentDataRange = NSMakeRange((NSUInteger)_currentRequest.dataRequest.requestedOffset, _currentRequest.dataRequest.requestedLength);
    
    //response
    if (!_response && self.cacheFile.responseHeaders.count > 0)
    {
        if (_currentDataRange.length == NSUIntegerMax)
        {
            _currentDataRange.length = [self.cacheFile fileLength] - _currentDataRange.location;
        }
        
        NSMutableDictionary *responseHeaders = [self.cacheFile.responseHeaders mutableCopy];
        NSString *contentRangeKey = @"Content-Range";
        BOOL supportRange = responseHeaders[contentRangeKey] != nil;
        if (supportRange && MCValidByteRange(_currentDataRange))
        {
            responseHeaders[contentRangeKey] = MCRangeToHTTPRangeReponseHeader(_currentDataRange, [self.cacheFile fileLength]);
        }
        else
        {
            [responseHeaders removeObjectForKey:contentRangeKey];
        }
        responseHeaders[@"Content-Length"] = [NSString stringWithFormat:@"%tu",_currentDataRange.length];

        NSInteger statusCode = supportRange ? 206 : 200;
        _response = [[NSHTTPURLResponse alloc] initWithURL:_currentRequest.request.URL statusCode:statusCode HTTPVersion:@"HTTP/1.1" headerFields:responseHeaders];
        [_currentRequest mc_fillContentInformation:_response];

    }
    [self startCurrentRequest];
}

- (void)startCurrentRequest
{
    NSOperationQueue * queue = [self queueForRequest:_currentRequest];
    queue.suspended = YES;
    
    if (_currentDataRange.length == NSUIntegerMax)
    {
        [self addTaskWithRange:NSMakeRange(_currentDataRange.location, NSUIntegerMax) cached:NO];
    }
    else
    {
        
        NSUInteger start = _currentDataRange.location;
        NSUInteger end = NSMaxRange(_currentDataRange);
        while (start < end)
        {
            NSRange firstNotCachedRange = [self.cacheFile firstNotCachedRangeFromPosition:start];
            if (!MCValidFileRange(firstNotCachedRange))
            {
                [self addTaskWithRange:NSMakeRange(start, end - start) cached:self.cacheFile.cachedDataBound > 0];
                start = end;
            }
            else if (firstNotCachedRange.location >= end)
            {
                [self addTaskWithRange:NSMakeRange(start, end - start) cached:YES];
                start = end;
            }
            else if (firstNotCachedRange.location >= start)
            {
                if (firstNotCachedRange.location > start)
                {
                    [self addTaskWithRange:NSMakeRange(start, firstNotCachedRange.location - start) cached:YES];
                }
                NSUInteger notCachedEnd = MIN(NSMaxRange(firstNotCachedRange), end);
                [self addTaskWithRange:NSMakeRange(firstNotCachedRange.location, notCachedEnd - firstNotCachedRange.location) cached:NO];
                start = notCachedEnd;
            }
            else
            {
                [self addTaskWithRange:NSMakeRange(start, end - start) cached:YES];
                start = end;
            }
        }
    }
    queue.suspended = NO;
}

- (void)completeRequest:(AVAssetResourceLoadingRequest *)loadingRequest task:(NSError *)error {
    if (error) {
        if (![loadingRequest isFinished]) {
            [loadingRequest finishLoadingWithError:error];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:SQRRemoteResponseIsNotAudioNotification object:self userInfo:@{AVPlayerItemFailedToPlayToEndTimeErrorKey:error}];
        }
    }else {
        if (![loadingRequest isFinished]) {
            [loadingRequest finishLoading];
        }
    }
    
    [self removeTaskQueue:loadingRequest];
}

- (void)cleanUpCurrentRequest
{
    [_pendingRequests removeObject:_currentRequest];
    _currentRequest = nil;
    _response = nil;
    _currentDataRange = MCInvalidRange;
}

- (void)addTaskWithRange:(NSRange)range cached:(BOOL)cached
{
    NSOperationQueue * queue = [self queueForRequest:_currentRequest];

    SQRPlayerItemCacheTask *task = nil;
    if (cached)
    {
        task = [[SQRPlayerItemLocalCacheTask alloc] initWithCacheFile:self.cacheFile loadingRequest:_currentRequest range:range];
        LOG_I(@"创建本地任务:  %@ \n",NSStringFromRange(range));
    }
    else
    {
        task = [[SQRPlayerItemRemoteCacheTask alloc] initWithCacheFile:self.cacheFile loadingRequest:_currentRequest range:range];
        [(SQRPlayerItemRemoteCacheTask *)task setResponse:_response];
        LOG_I(@"创建远程任务(%@) \n,",NSStringFromRange(range));
    }
    
    __weak typeof(self)weakSelf = self;
    task.finishBlock = ^(SQRPlayerItemCacheTask *task, NSError *error)
    {
        if (task.cancelled || error.code == NSURLErrorCancelled)
        {
            return;
        }
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        if (error)
        {
            LOG_E(@"cache loader load Data failed. ranage: %@ : %@",NSStringFromRange(range),error);
            [strongSelf completeRequest:task.loadingRequest task:error];
        }
        else
        {
            if (queue.operationCount<=1) {
                [strongSelf completeRequest:task.loadingRequest task:nil];
            }
        }
        
#ifdef SingleQueue
        LOG_I(@"请求成功，当前队列任务数:  %lu/ 1",queue.operationCount);
#else
        LOG_I(@"请求成功，当前队列任务数:  %lu/%lu",queue.operationCount,_queues.count);
#endif
    };
    [queue addOperation:task];

#ifdef SingleQueue
    LOG_I(@"队列任务数:  %lu/ 1",queue.operationCount);
#else
    LOG_I(@"队列任务数:  %lu/%lu",queue.operationCount,_queues.count);
#endif
}

#pragma mark - tasks 

- (NSString *)keyForLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSString * urlString = loadingRequest.request.URL.absoluteString;
    if (!urlString) {
        urlString = @"no_url";
    }
    NSString * url      = [urlString mc_md5];
    NSString * range    = [NSString stringWithFormat:@"?range=%lli-%lu",loadingRequest.dataRequest.requestedOffset,(long int)loadingRequest.dataRequest.requestedLength];
    
#ifdef SingleQueue
    return @"custom queue";
#endif
    return [url stringByAppendingString:range];
}

- (void)addTaskQueue:(AVAssetResourceLoadingRequest *)loadingRequest {
    [self cancelAllQueue];
    
#ifdef SingleQueue
    return;
#endif
    NSOperationQueue * queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 5;
    queue.name = [self keyForLoadingRequest:loadingRequest];
    
    _queues[[self keyForLoadingRequest:loadingRequest]] = queue;
    
    LOG_I(@"create new queue:  %@",queue.name);
}

- (void)removeTaskQueue:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSString * key = [self keyForLoadingRequest:loadingRequest];
    
    NSOperationQueue * queue = [_queues objectForKey:key];
    if (queue) {
        [queue.operations makeObjectsPerformSelector:@selector(sqr_cancel)];
        [queue cancelAllOperations];
        [_queues removeObjectForKey:key];
        LOG_I(@"remove queue:  %@",queue.name);
    }
}

- (NSOperationQueue *)queueForRequest:(AVAssetResourceLoadingRequest *)loadingRequet {
#ifdef SingleQueue
    return _singleQueue;
#endif
    
    NSOperationQueue * queue = self.queues[[self keyForLoadingRequest:loadingRequet]];
    return queue;
}

- (void)cancelAllQueue {
#ifdef SingleQueue
    [_singleQueue cancelAllOperations];
#endif
    
    for (NSOperationQueue * queue in _queues.allValues) {
        [queue.operations makeObjectsPerformSelector:@selector(sqr_cancel)];
        [queue cancelAllOperations];
    }
    [_queues removeAllObjects];
}

#pragma mark - resource loader delegate
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
    [_pendingRequests addObject:loadingRequest];
    [self addTaskQueue:loadingRequest];
    [self startNextRequest];
    
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    
    LOG_I(@"播放器取消之前请求。 范围：: Offset:%lld  currentOffset:%lld  Length:%ld >", loadingRequest.dataRequest.requestedOffset, loadingRequest.dataRequest.currentOffset, loadingRequest.dataRequest.requestedLength);

    [_pendingRequests removeObject:loadingRequest];
    [self removeTaskQueue:loadingRequest];
    
    return;
}
@end
