//
//  SQRPlayer.h
//  AVFoundationQueuePlayer-iOS
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SQRMediaItem.h"
#import <AVFoundation/AVFoundation.h>


@class SQRPlayer;

typedef NS_ENUM(NSUInteger, SQRMediaPlaybackState) {
    SQRMediaPlaybackStateStopped = 0,
    SQRMediaPlaybackStatePlaying,
    SQRMediaPlaybackStatePaused,
    SQRMediaPlaybackStateLoading
};



@protocol SQRMediaPlayerDelegate <NSObject>
@required
- (BOOL)mediaPlayerWillStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item;
@optional
/// 播放进度
- (void)mediaPlayerDidChangedPlaybackTime:(SQRPlayer *)player;
/// 缓冲进度
- (void)mediaPlayerDidUpdateBufferProgress:(float)progress player:(SQRPlayer *)player media:(SQRMediaItem *)item;

- (void)mediaPlayerWillStartLoading:(SQRPlayer *)player media:(SQRMediaItem *)item;
- (void)mediaPlayerDidEndLoading:(SQRPlayer *)player media:(SQRMediaItem *)item;

- (void)mediaPlayerWillChangeState:(SQRPlayer *)player state: (SQRMediaPlaybackState)state;
- (void)mediaPlayerDidStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item;
- (void)mediaPlayerDidSFinishPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item;
- (void)mediaPlayerDidStop:(SQRPlayer *)player media:(SQRMediaItem *)item;
- (void)mediaPlayerDidFailedWithError:(NSError *)error player:(SQRPlayer *)player media:(SQRMediaItem *)item;
- (void)mediaPlayerRetryNext:(SQRPlayer *)player error:(NSError *)error media:(SQRMediaItem *)item;

/// 应用程序被中断
- (void)mediaPlayerDidInterrupt:(SQRPlayer *)player interruptState:(AVAudioSessionInterruptionType)type;
/**
 切换音频输出
 * 切换到扬声器时，暂停播放
 * 切换到耳机、蓝牙等，继续播放

 @param player 当前播放器
 */
- (void)mediaPlayerDidChangeAudioRoute:(SQRPlayer *)player;


/// 锁屏时显示的图像. 在 SQRMediaItem来不及获取 图像时使用
- (UIImage *)mediaPlayerArtworkImage:(SQRPlayer *)player media:(SQRMediaItem *)item;


@end


@interface SQRPlayer : NSObject
@property (nonatomic, weak) id<SQRMediaPlayerDelegate>delegate;
@property (nonatomic, assign, readonly) SQRMediaPlaybackState playbackState;


+ (instancetype)sharePlayer;

/* 播放 暂停 停止*/
- (void)play;
- (void)pause;
- (void)stop;

/* 添加媒体 移除媒体 替换媒体*/
- (void)addPlayItem:(SQRMediaItem *)item;
- (void)removePlayItemAt:(NSUInteger)index;
- (void)replaceMediaAtIndex:(SQRMediaItem *)media index:(NSInteger)index;

/* 设置播放队列  移除播放队列*/
- (void)setQueue:(NSArray <SQRMediaItem *>*)playList;
- (NSArray *)queue;
- (void)removeAllQueue;

/* 播放某个媒体  下一首  上一首*/
- (void)playMedia:(SQRMediaItem *)item;
- (void)playNextItem;
- (void)playPreviouseItem;

/** 获取当前播放item*/
- (SQRMediaItem *)currentPlayItem;

- (void)prepareToPlay:(SQRMediaItem *)item complete:(void(^)(AVPlayerItem *avitem, NSError *error))completeHandle;
/* 快进 */
- (void)seekTo:(NSTimeInterval)time;

/* 当前播放进度   当前播放总时长*/
- (NSTimeInterval)currentPlaybackTime;
- (NSTimeInterval)currentPlaybackDuration;
@end



@interface SQRPlayer (Handler)

/**
 向播放器注册协议处理者。暂支持协议：
 
 * <SQRPlayerNetworkChangedProtocol>
 
 @param handler 协议处理者
 @param protocol 协议
 */
+ (void)registHandler:(id)handler protocol:(Protocol *)protocol;
@end


@interface SQRPlayer (Cache)

/**
 设置播放器缓存过期时间和文件上限

 @param cacheMaxCount 文件个数上限。 default is 10. 小于0忽略上限
 @param secondsAgo 文件过期时间（秒）. default is 24*60*60。 小于0忽略文件过期
 */
- (void)setCacheMaxCount:(NSInteger)cacheMaxCount expireTime:(NSInteger)secondsAgo;

/**
 删除所有音频缓存目录

 @return 错误信息
 */
- (NSError *)removeAllCache;
@end
