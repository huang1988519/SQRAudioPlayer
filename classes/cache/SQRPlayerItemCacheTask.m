
//  Created by huanwh on 2017/7/31.

//

#import "SQRPlayerItemCacheTask.h"

@interface SQRPlayerItemCacheTask ()

@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;

@end

@implementation SQRPlayerItemCacheTask
@synthesize executing = _executing;
@synthesize finished = _finished;

- (instancetype)initWithCacheFile:(SQRPlayerItemCacheFile *)cacheFile loadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest range:(NSRange)range
{
    self = [super init];
    if (self)
    {
        _loadingRequest = loadingRequest;
        _range = range;
        _cacheFile = cacheFile;
    }
    return self;
}

- (void)main
{
    @autoreleasepool
    {
        [self setFinished:NO];
        [self setExecuting:YES];
        if (_finishBlock)
        {
            _finishBlock(self,nil);
        }
        
        [self setExecuting:NO];
        [self setFinished:YES];
    }
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

- (void)sqr_cancel {
    
}

@end
