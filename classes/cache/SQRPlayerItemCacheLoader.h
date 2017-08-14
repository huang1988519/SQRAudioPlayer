
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
 删除过期数据

 @param maxFileCount 设置保留缓存最大个数. 小于0，忽略文件上限
 @param seconds 删除多久之前数据. 小于0,忽略过期时间
 @return 错误信息
 */
+ (NSError *)removeExpireFiles:(NSInteger)maxFileCount beforeTime:(NSInteger)seconds;
/**
 *  清理所有音频缓存
 
 *  return 返回执行删除时错误
 */
+ (NSError *)removeAllAudioCache;

@end
