
//
// Created by huanwh on 2017/7/31.

//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVAssetResourceLoader.h>

@interface SQRPlayerItemCacheLoader : NSObject<AVAssetResourceLoaderDelegate>

@property (nonatomic,readonly) NSString *cacheFilePath;

+ (instancetype)cacheLoaderWithCacheFilePath:(NSString *)cacheFilePath;
- (instancetype)initWithCacheFilePath:(NSString *)cacheFilePath;
+ (void)removeCacheWithCacheFilePath:(NSString *)cacheFilePath;

/**
 删除过期文件
 
  * 一天之前的文件删除
  * 超过十个上限的文件删除
 */
+ (void)removeExpireFiles;
/**
 *  清理所有音频缓存
 */
+ (void)removeAllAudioCache;
@end
