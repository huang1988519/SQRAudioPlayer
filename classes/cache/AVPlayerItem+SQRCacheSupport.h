
//  Created by huanwh on 2017/7/31.

#import <AVFoundation/AVFoundation.h>

AVF_EXPORT NSString *const AVPlayerMCCacheErrorDomain NS_AVAILABLE(10_9, 7_0);

typedef NS_ENUM(NSUInteger, AVPlayerMCCacheError)
{
    AVPlayerMCCacheErrorFileURL = -1111900,
    AVPlayerMCCacheErrorSchemeNotHTTP = -1111901,
    AVPlayerMCCacheErrorUnsupportFormat = -1111902,
    AVPlayerMCCacheErrorCreateCacheFileFailed = -1111903,
};

@interface AVPlayerItem (SQRCacheSupport)

/**
 *  获取原始url，不要使用 [(AVURLAsset *)self.asset URL].
 */
@property (nonatomic,copy,readonly) NSURL *mc_URL;

/**
 *  cache path
 */
@property (nonatomic,copy,readonly) NSString *mc_cacheFilePath NS_AVAILABLE(10_9, 7_0);

@property (nonatomic,assign) BOOL assetLoaded;

/**
 *  本地的 AVPlayerItem, 等同  -mc_playerItemWithRemoteURL:URL options:nil error:error
 *
 *  @param URL     original request url
 *
 *  @return 本地 AVPlayerItem
 */
+ (instancetype)mc_playerItemWithRemoteURL:(NSURL *)URL error:(NSError **)error NS_AVAILABLE(10_9, 7_0);

/**
 *  生成路由本地的 AVPlayerItem, 等同  -mc_playerItemWithRemoteURL:URL options:options cacheFilePath:nil error:error
 *
 *  @param URL     original request url
 *  @param options 初始化 AVURLAsset的配置字典 .  AVURLAssetPreferPreciseDurationAndTimingKey and AVURLAssetReferenceRestrictionsKey
 *
 *  @return 本地 AVPlayerItem
 */
+ (instancetype)mc_playerItemWithRemoteURL:(NSURL *)URL options:(NSDictionary<NSString *, id> *)options error:(NSError **)error NS_AVAILABLE(10_9, 7_0);

/**
 *  生成路由本地的 AVPlayerItem
 *
 *  @param URL           original request url
 *  @param options       初始化 AVURLAsset的配置字典 .  AVURLAssetPreferPreciseDurationAndTimingKey and AVURLAssetReferenceRestrictionsKey
 *
 *  @param cacheFilePath 设置缓存路径, 如果设置nil，  则默认 Caches/AVPlayerMCCache
 *  @param error         nil,没有错误则返回. 失败, 媒体流不被缓存
 *
 *  @return 本地 AVPlayerItem
 */
+ (instancetype)mc_playerItemWithRemoteURL:(NSURL *)URL options:(NSDictionary<NSString *, id> *)options cacheFilePath:(NSString *)cacheFilePath error:(NSError **)error NS_AVAILABLE(10_9, 7_0);

/**
 *  移除本地缓存文件 和 index 文件
 *
 *  @param cacheFilePath 缓存文件路径
 */
+ (void)mc_removeCacheWithCacheFilePath:(NSString *)cacheFilePath NS_AVAILABLE(10_9, 7_0);

/**
 删除过期数据
 
 @param maxFileCount 设置保留缓存最大个数
 @param seconds 删除多久之前数据
 @return 错误信息
 */
+ (NSError *)removeExpireFiles:(NSInteger)maxFileCount beforeTime:(NSInteger)seconds;
+ (NSError *)removeAllAudioCache;
@end
