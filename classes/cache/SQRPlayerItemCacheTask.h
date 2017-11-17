
//
//  Created by huanwh on 2017/7/31.

#import <Foundation/Foundation.h>

@class SQRPlayerItemCacheTask;
typedef void (^SQRPlayerItemCacheTaskFinishedBlock)(SQRPlayerItemCacheTask *task,NSError *error);

@class SQRPlayerItemCacheFile;
@class AVAssetResourceLoadingRequest;

@interface SQRPlayerItemCacheTask : NSOperation
{
@protected
    NSRange _range;
    SQRPlayerItemCacheFile *_cacheFile;
}

@property (nonatomic,copy) SQRPlayerItemCacheTaskFinishedBlock finishBlock;
@property (nonatomic,weak) AVAssetResourceLoadingRequest *loadingRequest;
- (instancetype)initWithCacheFile:(SQRPlayerItemCacheFile *)cacheFile loadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest range:(NSRange)range;

- (void)sqr_cancel;
@end
