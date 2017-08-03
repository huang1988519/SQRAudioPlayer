//
//  SQRPlayer.h
//  AVFoundationQueuePlayer-iOS
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SQRMediaItem.h"

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

- (void)mediaPlayerWillChangeState:(SQRMediaPlaybackState)state;
- (void)mediaPlayerDidStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item;
- (void)mediaPlayerDidSFinishPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item;
- (void)mediaPlayerDidStop:(SQRPlayer *)player media:(SQRMediaItem *)item;
- (void)mediaPlayerDidFailedWithError:(NSError *)error player:(SQRPlayer *)player media:(SQRMediaItem *)item;

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

/* 快进 */
- (void)seekTo:(NSTimeInterval)time;

/* 当前播放进度   当前播放总时长*/
- (NSTimeInterval)currentPlaybackTime;
- (NSTimeInterval)currentPlaybackDuration;
@end
