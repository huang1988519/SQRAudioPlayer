
//
// Created by huanwh on 2017/7/31.
//  Copyright © 2016年 Chengyin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVAssetResourceLoader.h>

@interface SQRPlayerItemCacheLoader : NSObject<AVAssetResourceLoaderDelegate>

@property (nonatomic,readonly) NSString *cacheFilePath;

+ (instancetype)cacheLoaderWithCacheFilePath:(NSString *)cacheFilePath;
- (instancetype)initWithCacheFilePath:(NSString *)cacheFilePath;
+ (void)removeCacheWithCacheFilePath:(NSString *)cacheFilePath;
@end
