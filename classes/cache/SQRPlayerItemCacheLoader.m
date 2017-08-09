
//  Created by huanwh on 2017/7/31.

//

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
    SQRPlayerItemCacheFile *_cacheFile;
    NSHTTPURLResponse *_response;
}
@property (nonatomic,strong) NSMutableDictionary * queues;
@end

@implementation SQRPlayerItemCacheLoader

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
        _cacheFile = [SQRPlayerItemCacheFile cacheFileWithFilePath:cacheFilePath];
        if (!_cacheFile)
        {
            return nil;
        }
        _queues          = [NSMutableDictionary dictionary];
        _pendingRequests = [[NSMutableArray alloc] init];
        _currentDataRange = MCInvalidRange;
    }
    return self;
}

- (NSString *)cacheFilePath
{
    return _cacheFile.cacheFilePath;
}

+ (void)removeCacheWithCacheFilePath:(NSString *)cacheFilePath
{
    [[NSFileManager defaultManager] removeItemAtPath:cacheFilePath error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[cacheFilePath stringByAppendingString:[SQRPlayerItemCacheFile indexFileExtension]] error:NULL];
}

+ (void)removeExpireFiles {
    NSString * dirPath = MCCacheTemporaryDirectory();
    NSDirectoryEnumerator * fileEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:dirPath];
    
    NSMutableDictionary * validFiles = [NSMutableDictionary dictionary];
    for (NSString * fileName in fileEnumerator) {
        NSString * filePath = [dirPath stringByAppendingPathComponent:fileName];
        
        NSError * error = nil;
        NSDictionary * attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
        if (error) {
            LOG_I(@"get file attribuation error . %@",error);
            error = nil;
        }
        
        NSDate * lastModifyDate = [attrs objectForKey:NSFileModificationDate];
        NSDate * oneDayAge      = [NSDate dateWithTimeIntervalSinceNow:-60*60*24];
        
        if ([lastModifyDate compare:oneDayAge] == NSOrderedDescending) {
            if ([fileName.pathExtension isEqualToString:[SQRPlayerItemCacheFile indexFileExtension]] == false) {
                [[self class] removeCacheWithCacheFilePath:fileName];
            }else {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
                if (error) {
                    NSLog(@"delete file error. %@",error);
                    error = nil;
                }
            }
        }else {
            [validFiles setObject:filePath forKey:lastModifyDate];
        }
        
        if (validFiles.count > 10) {
            NSArray * filterKeys = [validFiles.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSDate *  _Nonnull obj1, NSDate *  _Nonnull obj2) {
                return [obj1 compare:obj2];
            }];
            
            int i = (int)filterKeys.count - 10;
            while (i > 0) {
                NSString * earlyPath = [validFiles objectForKey:filterKeys[i-1]];
                [[NSFileManager defaultManager] removeItemAtPath:earlyPath error:&error];
                if (error) {
                    LOG_E(@" delete file error. %@",error);
                    error = nil;
                }
                
                [validFiles removeObjectForKey:filterKeys.firstObject];
                i--;
            }
        }
    }
}

+ (void)removeAllAudioCache {
    NSString * dirPath = MCCacheTemporaryDirectory();
    
    NSError * error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:dirPath error:&error];
    if (error) {
        LOG_E(@"remove audio cache dir failed",nil);
    }
}


- (void)dealloc
{
    for (NSOperationQueue * queue in _queues.allValues) {
        [queue cancelAllOperations];
        [queue.operations makeObjectsPerformSelector:@selector(cancel)];
    }
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
    /*
    //data range
    if ([_currentRequest.dataRequest respondsToSelector:@selector(requestsAllDataToEndOfResource)] && _currentRequest.dataRequest.requestsAllDataToEndOfResource)
    {
        _currentDataRange = NSMakeRange((NSUInteger)_currentRequest.dataRequest.requestedOffset, NSUIntegerMax);
    }
    else
    {
        _currentDataRange = NSMakeRange((NSUInteger)_currentRequest.dataRequest.requestedOffset, _currentRequest.dataRequest.requestedLength);
    }
     */
    
    // 去除设置最大值，从网络获取的逻辑
    _currentDataRange = NSMakeRange((NSUInteger)_currentRequest.dataRequest.requestedOffset, _currentRequest.dataRequest.requestedLength);
    
    //response
    if (!_response && _cacheFile.responseHeaders.count > 0)
    {
        if (_currentDataRange.length == NSUIntegerMax)
        {
            _currentDataRange.length = [_cacheFile fileLength] - _currentDataRange.location;
        }
        
        NSMutableDictionary *responseHeaders = [_cacheFile.responseHeaders mutableCopy];
        NSString *contentRangeKey = @"Content-Range";
        BOOL supportRange = responseHeaders[contentRangeKey] != nil;
        if (supportRange && MCValidByteRange(_currentDataRange))
        {
            responseHeaders[contentRangeKey] = MCRangeToHTTPRangeReponseHeader(_currentDataRange, [_cacheFile fileLength]);
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
    NSOperationQueue * queue = self.queues[_currentRequest.request.URL.absoluteString];
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
            NSRange firstNotCachedRange = [_cacheFile firstNotCachedRangeFromPosition:start];
            if (!MCValidFileRange(firstNotCachedRange))
            {
                [self addTaskWithRange:NSMakeRange(start, end - start) cached:_cacheFile.cachedDataBound > 0];
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
        [loadingRequest finishLoadingWithError:error];
    }else {
        if (![loadingRequest isFinished]) {
            [loadingRequest finishLoading];
        }
    }
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
    NSOperationQueue * queue = self.queues[[self keyForLoadingRequest:_currentRequest]];

    SQRPlayerItemCacheTask *task = nil;
    if (cached)
    {
        task = [[SQRPlayerItemLocalCacheTask alloc] initWithCacheFile:_cacheFile loadingRequest:_currentRequest range:range];
        LOG_I(@"添加 本地 队列  %@  \n at queue %@ \n",NSStringFromRange(range),queue.name);
    }
    else
    {
        task = [[SQRPlayerItemRemoteCacheTask alloc] initWithCacheFile:_cacheFile loadingRequest:_currentRequest range:range];
        [(SQRPlayerItemRemoteCacheTask *)task setResponse:_response];
        LOG_I(@"添加 远程 队列  %@ \n at queue %@ \n,",NSStringFromRange(range),queue.name);
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
            [strongSelf completeRequest:task.loadingRequest task:error];
        }
        else
        {
            if (queue.operationCount<=1) {
                [strongSelf completeRequest:task.loadingRequest task:nil];
            }
        }
    };
    [queue addOperation:task];
    
    LOG_I(@"当前队列 %lu / %lu",queue.operationCount,_queues.count);
}

#pragma mark - tasks 

- (NSString *)keyForLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSString * url      = loadingRequest.request.URL.absoluteString;
    NSString * range    = [NSString stringWithFormat:@"?range=%lld-%ld",loadingRequest.dataRequest.requestedOffset,loadingRequest.dataRequest.requestedLength];
    
    return [url stringByAppendingString:range];
}

- (void)addTaskQueue:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSOperationQueue * queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
    queue.name = [self keyForLoadingRequest:loadingRequest];
    
    _queues[[self keyForLoadingRequest:loadingRequest]] = queue;
    
    LOG_I(@"创建队列 %@",queue.name);
}

- (void)removeTaskQueue:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSOperationQueue * queue = _queues[[self keyForLoadingRequest:loadingRequest]];
    if (queue) {
        [queue cancelAllOperations];
        [queue.operations makeObjectsPerformSelector:@selector(cancel)];
    }
    
    [_queues removeObjectForKey:[self keyForLoadingRequest:loadingRequest]];
    
    LOG_I(@"移除 队列 %@",queue.name);
}

#pragma mark - resource loader delegate
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
    if ([[[loadingRequest request] URL] isFileURL]) {
        return NO;
    }
    
    [_pendingRequests addObject:loadingRequest];
    [self addTaskQueue:loadingRequest];
    [self startNextRequest];
    
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    [_pendingRequests removeObject:loadingRequest];
    [self removeTaskQueue:loadingRequest];
    
    return;
}
@end
