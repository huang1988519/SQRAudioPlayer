
//  Created by huanwh on 2017/7/31.
//  Copyright © 2016年 Chengyin. All rights reserved.
//

#import "SQRPlayerItemLocalCacheTask.h"
#import "SQRPlayerItemCacheFile.h"
#import "SQRCacheSupportUtils.h"

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
                break;
            }
            @autoreleasepool
            {
                NSRange range = NSMakeRange(offset, MIN(NSMaxRange(_range) - offset,lengthPerRead));
                NSData *data = [_cacheFile dataWithRange:range];
                [_loadingRequest.dataRequest respondWithData:data];
                offset = NSMaxRange(range);
            }
        }
        [self handleFinished];
    }
}

- (void)handleFinished
{
    if (self.finishBlock)
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
