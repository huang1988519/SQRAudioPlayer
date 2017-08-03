//
//  SQRPlayer.m
//  AVFoundationQueuePlayer-iOS
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 Apple Inc. All rights reserved.
//

#import "SQRPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "AVPlayerItem+SQRCacheSupport.h"
#import <MediaPlayer/MediaPlayer.h>

@interface SQRPlayer()
{
    id<NSObject>_timeObserver;
    NSInteger _playingIndex;
}
@property (nonatomic, strong)AVQueuePlayer * player;
@property (nonatomic, strong)SQRMediaItem  * currentPlayItem;

@property (nonatomic, strong)NSMutableArray *playItemQueue;
@end

@implementation SQRPlayer

static void *kSQRAudioControllerBufferingObservationContext = &kSQRAudioControllerBufferingObservationContext;

static NSString *const kSQRLoadedTimeRangesKeyPath = @"loadedTimeRanges";

static SQRPlayer * instancePlayer;
+(instancetype)sharePlayer {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instancePlayer = [[self class] new];
    });
    
    return instancePlayer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _playingIndex = 0;
        
        _player = [[AVQueuePlayer alloc] init];
        _playItemQueue = [NSMutableArray array];
    }
    return self;
}

-(void)dealloc {
    if (_timeObserver) {
        [self.player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
    
    [self removePlayItemReachEndNotifcation];
    
    [self.player pause];
}

- (void)addPlayerItemObservers {
    [self.player.currentItem addObserver:self forKeyPath:kSQRLoadedTimeRangesKeyPath options:NSKeyValueObservingOptionNew context:&kSQRAudioControllerBufferingObservationContext];
}
- (void)removePlayerItemObservers {
    @try {
        [self.player.currentItem removeObserver:self forKeyPath:kSQRLoadedTimeRangesKeyPath];
    } @catch(NSException *exception) {
        NSLog(@"[player error]remove observer failed: %@",exception);
    }
    
}

- (void)loadAssetValues:(SQRMediaItem *)item {
    
    AVPlayerItem * newPlayItem = [AVPlayerItem mc_playerItemWithRemoteURL:item.assetUrl error:nil];
    
    __weak AVAsset * weakAsset = newPlayItem.asset;
    __weak typeof(self)weakSelf = self;

    [newPlayItem.asset loadValuesAsynchronouslyForKeys:[self.class assetKeysRequiredToPlay] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf)strongself = weakSelf;
            
            if ([self.delegate respondsToSelector:@selector(mediaPlayerDidEndLoading:media:)]) {
                [self.delegate mediaPlayerDidEndLoading:self media:item];
            }
            
            NSArray * allKeys = [self.class assetKeysRequiredToPlay];
            
            for (NSString * key in allKeys) {
                NSError * error = nil;
                if ([weakAsset statusOfValueForKey:key error:&error] != AVKeyValueStatusLoaded) {
                    NSLog(@"player error: %@", error);
                    return;
                }
            }
            
            if (!weakAsset.playable || weakAsset.hasProtectedContent) {
                NSLog(@"player error: %@", @"audio cannot play");
                return;
            }
            
            NSError *error = nil;
            if (error) {
                NSLog(@"[sqrplayer error] cache failed");
                
                [strongself setCurrentState:SQRMediaPlaybackStateStopped];
                
                if ([strongself.delegate respondsToSelector:@selector(mediaPlayerDidFailedWithError:player:media:)]) {
                    [strongself.delegate mediaPlayerDidFailedWithError:error player:self media:item];
                }
            }
            else {
                // 加载新的asset
                strongself.player.usesExternalPlaybackWhileExternalScreenIsActive = YES;
                
                [strongself.player replaceCurrentItemWithPlayerItem:newPlayItem];
                [strongself play];
                
                [strongself addPlayerItemObservers];
                [strongself addPlayItemReachEndNotifcation];
                
                _timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
                    [weakSelf syncPlayProcess:time];
                }];
                
                if([strongself.delegate respondsToSelector:@selector(mediaPlayerDidStartPlaying:media:)]) {
                    [strongself.delegate mediaPlayerDidStartPlaying:strongself media:item];
                }
                
                weakSelf.currentPlayItem = item;
            }
            
        });
    }];
   
}
#pragma mark - play action

- (void)addPlayItem:(SQRMediaItem *)item {
    [self.playItemQueue addObject:item];
}


- (void)removePlayItemAt:(NSUInteger)index {
    if (index+1>self.playItemQueue.count) {
        NSLog(@"[player error] index is beyond range");
        return;
    }
    SQRMediaItem * item = _playItemQueue[index];
    if (item == _currentPlayItem) {
        _currentPlayItem = nil;
        [self playNextItem];
    }
    
    [self.playItemQueue removeObjectAtIndex:index];
}


- (void)replaceMediaAtIndex:(SQRMediaItem *)media index:(NSInteger)index {
    if (index > self.playItemQueue.count -1) {
        NSLog(@"[player error] index beyound  queue range");
        return;
    }
    SQRMediaItem * item = self.playItemQueue[index];
    if (item == _currentPlayItem) {
        _currentPlayItem = nil;
    }
    
    [self.playItemQueue replaceObjectAtIndex:index withObject:media];
}


- (void)setQueue:(NSArray <SQRMediaItem *>*)playList {
    [self stop];
    
    [self.playItemQueue removeAllObjects];
    [self.playItemQueue addObjectsFromArray:playList];
}

- (NSArray *)queue {
    NSArray * copyArray = [self.playItemQueue copy];
    return copyArray;
}


- (void)removeAllQueue {
    _currentPlayItem = nil;
    [self stop];
    [self.playItemQueue removeAllObjects];
}

-(void)playMedia:(SQRMediaItem *)item {
    _currentPlayItem = item;
    [self removePlayerItemObservers];
    [self stop];
    [self.player.currentItem.asset cancelLoading];
    
    if (self.delegate || !item) {
        if (![self.delegate respondsToSelector:@selector(mediaPlayerWillStartPlaying:media:)] ||
            [self.delegate mediaPlayerWillStartPlaying:self media:item] == NO ||
            !item) {
            return;
        }
    }
    
    _currentPlayItem = item;
    [self.player removeTimeObserver:_timeObserver];
    [self setCurrentState:SQRMediaPlaybackStateLoading];
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerWillStartLoading:media:)]) {
        [self.delegate mediaPlayerWillStartLoading:self media:item];
    }
    
    [self loadAssetValues:item];
}

- (void)playNextItem {
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidSFinishPlaying:media:)]) {
        [self.delegate mediaPlayerDidSFinishPlaying:self media:_currentPlayItem];
    }
    
    if (self.playItemQueue.count) {
        if (_playingIndex > self.playItemQueue.count -1) {
            _playingIndex = 0;
        }else {
            _playingIndex++;
        }
        
        [self playMedia:self.playItemQueue[_playingIndex]];
    }else {
    }
}

- (void)playPreviouseItem {
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidSFinishPlaying:media:)]) {
        [self.delegate mediaPlayerDidSFinishPlaying:self media:_currentPlayItem];
    }
    
    if (self.playItemQueue.count) {
        if ((_playingIndex - 1) < 0) {
            _playingIndex = self.playItemQueue.count -1;
        }else {
            _playingIndex--;
        }
        
        [self playMedia:self.playItemQueue[_playingIndex]];
    }
}

- (void)playMeidaAtIndex:(NSUInteger)index {
    if (index > self.playItemQueue.count-1) {
        NSLog(@"[player error] play index beyoud range");
        return;
    }
    _playingIndex = MAX(0, MIN(index, self.playItemQueue.count -1));
    [self playMedia:self.playItemQueue[_playingIndex]];
}


- (void)play {
    if (self.playbackState == SQRMediaPlaybackStateStopped) {
        [self.player seekToTime:CMTimeMake(0, 1)];
    }
    if (self.currentPlayItem == nil) {
        [self playMedia:self.playItemQueue.firstObject];
    }
    else {
        [self.player play];
    }
    
    [self setCurrentState:SQRMediaPlaybackStatePlaying];
}

- (void)pause {
    [self.player pause];
    
    [self setCurrentState:SQRMediaPlaybackStatePaused];
}

- (void)stop {
    [self.player pause];
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidStop:media:)]) {
        [self.delegate mediaPlayerDidStop:self media:_currentPlayItem];
    }
    _currentPlayItem = nil;
    
    [self removePlayItemReachEndNotifcation];
    [self removePlayerItemObservers];
    
    [self setCurrentState:SQRMediaPlaybackStateStopped];
}

-(void)seekTo:(NSTimeInterval)time {
    [self.player seekToTime:CMTimeMake(time, 1)];
}

- (void)setCurrentState:(SQRMediaPlaybackState)state {
    if (state == _playbackState) {
        return;
    }
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerWillChangeState:)]) {
        [self.delegate mediaPlayerWillChangeState:state];
    }
    
    if (state == SQRMediaPlaybackStatePlaying) {
        //  更新锁屏信息
        [self updatLockScreenInfo];
        
        NSError * error = nil;
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
        [audioSession setActive:YES error:NULL];
    }
    
    _playbackState = state;
}

- (void)updatLockScreenInfo {
    NSMutableDictionary * info = [NSMutableDictionary dictionary];
    [info setObject:_currentPlayItem.title ?: @"" forKey:MPMediaItemPropertyTitle];
    [info setObject:@([self currentPlaybackTime]) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [info setObject:@([self currentPlaybackDuration]) forKey:MPMediaItemPropertyPlaybackDuration];
    // 专辑名称
    [info setObject:[_currentPlayItem albumTitle] ?: @"" forKey:MPMediaItemPropertyAlbumTitle];
    // 艺术家
    [info setObject:[_currentPlayItem artist] ?: @"" forKey:MPMediaItemPropertyArtist];
    
    UIImage * coverImg = [_currentPlayItem artworkImage];
    if ([self.delegate respondsToSelector:@selector(mediaPlayerArtworkImage:media:)]) {
        coverImg = [self.delegate mediaPlayerArtworkImage:self media:_currentPlayItem];
    }
    if (coverImg) {
#ifdef __IPHONE_10_0
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(300, 300) requestHandler:^UIImage * _Nonnull(CGSize size) {
            return coverImg;
        }];
        [info setObject:artwork forKey:MPMediaItemPropertyArtwork];
#else
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage:coverImg];
        [info setObject:artwork forKey:MPMediaItemPropertyArtwork];
#endif
        
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
}


#pragma mark - play notification

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    AVPlayerItem * item = notification.object;
    if (self.player.currentItem == item) {
        [self playNextItem];
    }
    else {
        [self removePlayerItemObservers];
    }
}


- (void)addPlayItemReachEndNotifcation {
    
    [self removePlayItemReachEndNotifcation];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
}


- (void)removePlayItemReachEndNotifcation {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
}

#pragma mark - play info

- (NSTimeInterval)currentPlaybackTime {
    return self.player.currentTime.value == 0 ? 0: self.player.currentTime.value / self.player.currentTime.timescale;
}

- (NSTimeInterval)currentPlaybackDuration {
    return CMTimeGetSeconds([[self.player.currentItem asset] duration]);
}

#pragma mark -  Observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != kSQRAudioControllerBufferingObservationContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    
    AVPlayerItem* playerItem = (AVPlayerItem*)object;
    NSArray* times = playerItem.loadedTimeRanges;
    
    NSValue* value = [times firstObject];
    
    if(value) {
        CMTimeRange range;
        [value getValue:&range];
        float start = CMTimeGetSeconds(range.start);
        float duration = CMTimeGetSeconds(range.duration);
        
        CGFloat videoAvailable = start + duration;
        CGFloat totalDuration = CMTimeGetSeconds(self.player.currentItem.asset.duration);
        CGFloat progress = videoAvailable / totalDuration;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if([self.delegate respondsToSelector:@selector(mediaPlayerDidUpdateBufferProgress:player:media:)]) {
                [self.delegate mediaPlayerDidUpdateBufferProgress:progress player:self media:_currentPlayItem];
            }
        });
        
        NSLog(@"[player] steaming have cache %0.2f",progress);
    }
}

// 尝试加载对应key的内容
+ (NSArray *)assetKeysRequiredToPlay {
    return @[@"playable", @"hasProtectedContent"];
}

- (void)syncPlayProcess:(CMTime)time {
    //如果正在播放，刷新进度
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidChangedPlaybackTime:)]) {
        [self.delegate mediaPlayerDidChangedPlaybackTime:self];
    }
    
    NSLog(@"[player debug] playback %0.2f / %0.2f", CMTimeGetSeconds(time), CMTimeGetSeconds(self.player.currentItem.duration));
}
@end
