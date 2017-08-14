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
#import "SQRMediaPlayer.h"
#import "SQRPlayerHandlerFactory.h"

@interface SQRPlayer()
{
    __weak id<NSObject>_timeObserver;
    NSInteger _playingIndex;
    BOOL      _interrupt; // 是否是被外部应用打断
}
@property (nonatomic, strong)AVPlayer * player;
@property (nonatomic, strong)SQRMediaItem  * currentPlayItem;

@property (nonatomic, strong)AVAsset * loadingAsset;
@property (nonatomic, strong)NSMutableArray *playItemQueue;

/// 缓存最大上限
@property (nonatomic, assign)NSUInteger cacheMaxCount;
/// 缓存过期时间
@property (nonatomic, assign)NSUInteger expireTime;
@end

@implementation SQRPlayer

static void *kSQRAudioControllerBufferingObservationContext = &kSQRAudioControllerBufferingObservationContext;
static void *kSQRAudioControllerPlayStateObservationContext = &kSQRAudioControllerPlayStateObservationContext;


static NSString *const kSQRLoadedTimeRangesKeyPath = @"loadedTimeRanges";
static NSString *const kSQRPlayRateKeyPath = @"rate";

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
        _interrupt    = NO;
        
        _player = [[AVPlayer alloc] init];
        if ([_player respondsToSelector:@selector(setAutomaticallyWaitsToMinimizeStalling:)]) {
            _player.automaticallyWaitsToMinimizeStalling = NO;
        }
        _playItemQueue = [NSMutableArray array];
        
        _cacheMaxCount  = 10;
        _expireTime     = 24*60*60;
    }
    return self;
}

-(void)dealloc {
    if (_timeObserver) {
        [self.player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
    
    [self removePlayItemReachEndNotifcation];
    [self removeAudioSessionNotification];
    
    [self.player pause];
}

- (void)addPlayerItemObservers {
    [self.player.currentItem addObserver:self forKeyPath:kSQRLoadedTimeRangesKeyPath options:NSKeyValueObservingOptionNew context:&kSQRAudioControllerBufferingObservationContext];
    [self.player addObserver:self forKeyPath:kSQRPlayRateKeyPath options:NSKeyValueObservingOptionNew context:kSQRAudioControllerPlayStateObservationContext];

}
- (void)removePlayerItemObservers {
    @try {
        [self.player.currentItem removeObserver:self forKeyPath:kSQRLoadedTimeRangesKeyPath];
        [self.player removeObserver:self forKeyPath:kSQRPlayRateKeyPath];
    } @catch(NSException *exception) {
//        LOG_E(@"%@",@"[player error] remove observer failed");
    }
    
}

-(void)addTimeObserver {
    __weak typeof(self)weakSelf = self;
    if (!_timeObserver) {
        _timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [weakSelf syncPlayProcess:time];
        }];
    }
    
}

- (void)removeTimeObserver {
    if (_timeObserver) {
        [self.player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
    
}

- (NSError *)errorWithMesssage:(NSString *)msg code:(NSInteger)errorCode {
    return sqr_errorWithCode((int)errorCode, msg);
}

#pragma mark - load asset

- (void)loadAssetValues:(SQRMediaItem *)item complete:(void(^)(AVPlayerItem *item, NSError * error))completeHandle {
    if (_loadingAsset) {
        [_loadingAsset cancelLoading];
    }
    
    AVPlayerItem * newPlayItem = nil;
    NSURL * url = item.currentUrl;
    if ([url isFileURL]) {
        newPlayItem = [AVPlayerItem playerItemWithURL:url];
        
    }else {
        newPlayItem = [AVPlayerItem mc_playerItemWithRemoteURL:url error:nil];
    }
    
    _loadingAsset = newPlayItem.asset;

    __weak AVAsset * weakAsset = _loadingAsset;
    __weak typeof(self)weakSelf = self;
    
    [_loadingAsset loadValuesAsynchronouslyForKeys:[self.class assetKeysRequiredToPlay] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            
            __strong typeof(weakSelf)strongself = weakSelf;
            
            if ([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidEndLoading:media:)]) {
                [weakSelf.delegate mediaPlayerDidEndLoading:self media:item];
            }
            
            NSArray * allKeys = [self.class assetKeysRequiredToPlay];
            
            NSError * customeError = nil;
            for (NSString * key in allKeys) {
                NSError * error = nil;
                if ([weakAsset statusOfValueForKey:key error:&error] == AVKeyValueStatusFailed) {
                    LOG_E(@"player error: %@", error);
                    customeError = error;
                    break;
                }
            }
            
            if (!weakAsset.playable || weakAsset.hasProtectedContent) {
                LOG_E(@"player error: %@", @"audio cannot play");
                
                if (!customeError) {
                    customeError = [strongself errorWithMesssage:@"url can not to play" code:kMediaPlayerErrorCodeCannotPlay];
                    [AVPlayerItem mc_removeCacheWithCacheFilePath:newPlayItem.mc_cacheFilePath];
                }
            }
            // 递归多个url，寻找可播放url
            if (customeError && [item retryNext]) {
                if ([weakSelf.delegate respondsToSelector:@selector(mediaPlayerRetryNext:error:media:)]) {
                    [weakSelf.delegate mediaPlayerRetryNext:weakSelf error:customeError media:item];
                }
                [weakSelf loadAssetValues:item complete:completeHandle];
                return;
            }
            
            // 回调
            if (completeHandle) {
                completeHandle(newPlayItem, customeError);
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
        LOG_E(@"%@",@"index is beyond range");
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
        LOG_E(@"%@",@"[player error] index beyound  queue range");
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


- (void)prepareToPlay:(SQRMediaItem *)item complete:(void(^)(AVPlayerItem *avitem, NSError *error))completeHandle {
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
    
    [self setCurrentState:SQRMediaPlaybackStateLoading];
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerWillStartLoading:media:)]) {
        [self.delegate mediaPlayerWillStartLoading:self media:item];
    }

    __weak typeof(self)weakSelf = self;
    [self loadAssetValues:item complete:^(AVPlayerItem *avitem, NSError *error) {
        if (error) {
            [weakSelf setCurrentState:SQRMediaPlaybackStateStopped];
            [weakSelf.loadingAsset cancelLoading];
            weakSelf.loadingAsset = nil;
            
            if ([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidFailedWithError:player:media:)]) {
                [weakSelf.delegate mediaPlayerDidFailedWithError:error player:weakSelf media:item];
            }
        }else {

            // 清理缓存
            
            [[avitem class] removeExpireFiles:weakSelf.cacheMaxCount beforeTime:self.expireTime];
            
            if ([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidEndLoading:media:)]) {
                [weakSelf.delegate mediaPlayerDidEndLoading:weakSelf media:item];
            }
            
            // 加载新的asset
            weakSelf.player.usesExternalPlaybackWhileExternalScreenIsActive = YES;
            [weakSelf.player replaceCurrentItemWithPlayerItem:avitem];
            
            [weakSelf addPlayerItemObservers];
            [weakSelf addPlayItemReachEndNotifcation];
            [weakSelf addTimeObserver];
            
            if([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidStartPlaying:media:)]) {
                [weakSelf.delegate mediaPlayerDidStartPlaying:weakSelf media:item];
            }
            
            weakSelf.currentPlayItem = item;
        }
        if (completeHandle) {
            completeHandle(avitem,error);
        }
    }];
}

-(void)playMedia:(SQRMediaItem *)item {
    __weak typeof(self)weakSelf = self;

    [self prepareToPlay:item complete:^(AVPlayerItem *avitem, NSError *error) {
        if (error) {
        }else {
            [weakSelf play];
        }
    }];
}

- (void)playNextItem {
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidSFinishPlaying:media:)]) {
        [self.delegate mediaPlayerDidSFinishPlaying:self media:_currentPlayItem];
    }
    
    if (self.playItemQueue.count) {
        if (_playingIndex >= self.playItemQueue.count -1) {
            _playingIndex = 0;
        }else {
            _playingIndex++;
        }
        
        [self playMedia:self.playItemQueue[_playingIndex]];
    }else if(_playbackState != SQRMediaPlaybackStatePlaying) {
        LOG_I(@"%@",@"stop. becase player have reach queue end");
        [self stop];
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

- (SQRMediaItem *)currentPlayItem {
    return _currentPlayItem;
}

- (void)playMeidaAtIndex:(NSUInteger)index {
    if (index > self.playItemQueue.count-1) {
        LOG_E(@"%@",@"[player error] play index beyoud range");
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
        if (self.playItemQueue && _playingIndex < self.playItemQueue.count) {
            [self playMedia:self.playItemQueue[_playingIndex]];
        }else {
            [self playMedia:self.playItemQueue.firstObject];
        }
    }
    else {
        [self.player play];
    }
}

- (void)pause {
    [self.player pause];
}

- (void)stop {
    [self.player pause];
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidStop:media:)]) {
        [self.delegate mediaPlayerDidStop:self media:_currentPlayItem];
    }
    _currentPlayItem = nil;
    
    [self removePlayItemReachEndNotifcation];
    [self removePlayerItemObservers];
    [self removeTimeObserver];
    
    [self setCurrentState:SQRMediaPlaybackStateStopped];
}

-(void)seekTo:(NSTimeInterval)time {
    __weak typeof(self)weakSelf = self;
    if (self.player.status != AVPlayerStatusReadyToPlay) {
        LOG_I(@"seek to fast than player ready progress",nil);
        return;
    }
    [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        [weakSelf updatLockScreenInfo];
    }];
}

#pragma mark - 

- (void)setCurrentState:(SQRMediaPlaybackState)state {
    if (state == _playbackState) {
        return;
    }
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerWillChangeState:state:)]) {
        [self.delegate mediaPlayerWillChangeState:self state:state];
    }
    
    [self removeAudioSessionNotification];

    if (state == SQRMediaPlaybackStatePlaying) {
        //  更新锁屏信息
        [self updatLockScreenInfo];
        
        NSError * error = nil;
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
        [audioSession setActive:YES error:NULL];
        
        [self addAudioSessionNotification];
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
        NSString *version = [UIDevice currentDevice].systemVersion;
        if (version.doubleValue >= 10.0) {
            MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(300, 300) requestHandler:^UIImage * _Nonnull(CGSize size) {
                return coverImg;
            }];
            [info setObject:artwork forKey:MPMediaItemPropertyArtwork];
        }else {
            MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage:coverImg];
            [info setObject:artwork forKey:MPMediaItemPropertyArtwork];
        }
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

- (void)addAudioSessionNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionChangeRoute:) name:AVAudioSessionRouteChangeNotification object:nil];
}

- (void)removeAudioSessionNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
}

- (void)audioSessionInterrupted:(NSNotification *)notification {
    NSNumber *interruptionType = [[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey];
    AVAudioSessionInterruptionType type = interruptionType.unsignedIntegerValue;
    
    if ([_delegate respondsToSelector:@selector(mediaPlayerDidInterrupt:interruptState:)]) {
        [_delegate mediaPlayerDidInterrupt:self interruptState:type];
    }
}

- (void)audioSessionChangeRoute:(NSNotification *)notification {
    NSDictionary *dic=notification.userInfo;
    int changeReason= [dic[AVAudioSessionRouteChangeReasonKey] intValue];
    
    if (changeReason==AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        if (![AVAudioSession sharedInstance].currentRoute.outputs) {
            NSLog(@"切换到扬声器，音乐暂停");
            [self pause];
        }
        if([_delegate respondsToSelector:@selector(mediaPlayerDidChangeAudioRoute:)]) {
            [_delegate mediaPlayerDidChangeAudioRoute:self];
        }
    }
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
    if (context == kSQRAudioControllerBufferingObservationContext) {
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
            
            //        LOG_I(@"steaming have cache %0.2f",progress);
        }
        return;
    }
    else if (context == kSQRAudioControllerPlayStateObservationContext) {
        if (keyPath == kSQRPlayRateKeyPath) {
            NSNumber * rateNumber = change[NSKeyValueChangeNewKey];
            if ([rateNumber isKindOfClass:[NSNumber class]]) {
                float rate = [rateNumber floatValue];
                if (rate == 0.0) {
                    [self setCurrentState:SQRMediaPlaybackStatePaused];
                }else if (rate == 1.0) {
                    [self setCurrentState:SQRMediaPlaybackStatePlaying];
                }
            }
        }
        return;
    }
    
    
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];

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
    
//    LOG_I(@"[player debug] playback %0.2f / %0.2f", CMTimeGetSeconds(time), CMTimeGetSeconds(self.player.currentItem.duration));
}
@end





@implementation  SQRPlayer (Handler)

+ (void)registHandler:(id)handler protocol:(Protocol *)protocol {
    [SQRPlayerHandlerFactory resisterHandler:handler protocol:protocol];
}

@end


@implementation SQRPlayer (Cache)

- (void)setCacheMaxCount:(NSInteger)cacheMaxCount expireTime:(NSInteger)secondsAgo {
    self.cacheMaxCount = cacheMaxCount;
    self.expireTime = secondsAgo;
}

- (NSError *)removeAllCache {
    return [AVPlayerItem removeAllAudioCache];
}
@end
