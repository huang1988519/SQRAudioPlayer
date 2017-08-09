
//  Created by huanwh on 2017/7/31.

//

#import "SQRPlayerItemLocalCacheTask.h"
#import "SQRPlayerItemCacheFile.h"
#import "SQRCacheSupportUtils.h"
#import "SQRMediaPlayer.h"


@interface SQRPlayerItemLocalCacheTask ()

@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;

@end

@implementation SQRPlayerItemLocalCacheTask
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
        
        NSUInteger offset = _range.location;
        NSUInteger lengthPerRead = 10000;
        while (offset < NSMaxRange(_range))
        {
            if ([self isCancelled])
            {
                LOG_I(@"本地任务被中断",nil);
                break;
            }
            if (!_loadingRequest) {
                LOG_I(@"本地指向请求 被释放",nil);
                break;
            }
            @autoreleasepool
            {
                NSRange range = NSMakeRange(offset, MIN(NSMaxRange(_range) - offset,lengthPerRead));
                NSData *data = [_cacheFile dataWithRange:range];
                
                [_loadingRequest.dataRequest respondWithData:data];

                offset = NSMaxRange(range);
                
//                NSLog(@"返回 本地数据 %@", NSStringFromRange(range));
            }
        }
        [self handleFinished];
    }
}

- (void)handleFinished
{
    LOG_I(@"本地数据 读取结束. 范围 %@",NSStringFromRange(_range));
    
    if (self.finishBlock && _loadingRequest)
    {
        self.finishBlock(self,nil);
    }
    
    [self setExecuting:NO];
    [self setFinished:YES];
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
