
//
//  Created by huanwh on 2017/7/31.
//  Copyright © 2016年 Chengyin. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SQRPlayerItemCacheTask;
typedef void (^MCAVPlayerItemCacheTaskFinishedBlock)(SQRPlayerItemCacheTask *task,NSError *error);

@class SQRPlayerItemCacheFile;
@class AVAssetResourceLoadingRequest;
@interface SQRPlayerItemCacheTask : NSOperation
{
@protected
    AVAssetResourceLoadingRequest *_loadingRequest;
    NSRange _range;
    SQRPlayerItemCacheFile *_cacheFile;
}

@property (nonatomic,copy) MCAVPlayerItemCacheTaskFinishedBlock finishBlock;

- (instancetype)initWithCacheFile:(SQRPlayerItemCacheFile *)cacheFile loadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest range:(NSRange)range;
@end
