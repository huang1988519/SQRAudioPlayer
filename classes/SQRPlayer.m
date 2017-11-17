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
#import "SQRPlayerItemCacheFile.h"


NSString * const SQRCancelOrResumeAllRequestNotification = @"SQRCancelOrResumeAllRequestNotification";
NSString * const SQRRemoteResponseIsNotAudioNotification = @"NSString * const";

@interface SQRPlayer()
{
    __weak id<NSObject>_timeObserver;
    NSInteger _playingIndex;
    BOOL      _interrupt; // 是否是被外部应用打断
    BOOL      _buffering; // 是否正在加载数据
    BOOL      _isStalled; // 是否被阻塞
    BOOL      _cacheLoaderCanceled; // cacheLoader 被终止
}
@property (nonatomic, strong)AVPlayer * player;
@property (nonatomic, strong)SQRMediaItem  * currentItem;
@property (nonatomic, strong)AVPlayerItem  * loadingPlayItem;
@property (nonatomic, strong)NSTimer       * checkTimer;
@property (nonatomic, strong)NSMutableArray *playItemQueue;
/// 缓存最大上限
@property (nonatomic, assign)NSUInteger cacheMaxCount;
/// 缓存过期时间
@property (nonatomic, assign)NSUInteger expireTime;
@property (nonatomic, copy)  PrepareCompleteHandle readyHandle;

@property (nonatomic, assign)BOOL      curAssetLoaded; // 当前AVAsset是否被正确加载
@property (nonatomic, assign)BOOL      seeking;

@end



@implementation SQRPlayer

static void *kSQRAudioControllerBufferingObservationContext = &kSQRAudioControllerBufferingObservationContext;
static void *kSQRAudioControllerPlayStateObservationContext = &kSQRAudioControllerPlayStateObservationContext;
static void *kSQRAudioControllerPlayItemBufferObservationContext = &kSQRAudioControllerPlayItemBufferObservationContext;
static void *kSQRAudioControllerPlayItemLikeKeeyupObservationContext = &kSQRAudioControllerPlayItemLikeKeeyupObservationContext;
static void *kSQRAudioControllerPlayItemStatusObservationContext = &kSQRAudioControllerPlayItemStatusObservationContext;



static NSString *const kSQRLoadedTimeRangesKeyPath = @"loadedTimeRanges";
static NSString *const kSQRPlayRateKeyPath = @"rate";
static NSString *const kSQRPlayItemBufferStateKeyPath = @"playbackBufferEmpty";
static NSString *const kSQRPlayItemLikeToKeepupKeyPath = @"playbackLikelyToKeepUp";
static NSString *const kSQRPlayItemStatusKeyPath = @"status";


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
        _seeking      = NO;
        
        _player = [[AVPlayer alloc] init];
        [_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
        [_player addObserver:self forKeyPath:kSQRPlayRateKeyPath options:NSKeyValueObservingOptionNew context:kSQRAudioControllerPlayStateObservationContext];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recieveInvalidResponse:) name:SQRRemoteResponseIsNotAudioNotification object:nil];
        [self addTimeObserver];

        [self addPlayItemNotifcation];

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
    [self.player pause];

    [self removeTimeObserver];
    [self removePreloadAsset];
    [self stopCheckTimer];
    
    
    [self removePlayItemNotifcation];
    [self removeObservers];
    
    [_player removeObserver:self forKeyPath:@"status"];
    [_player removeObserver:self forKeyPath:kSQRPlayRateKeyPath];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}



- (NSError *)errorWithMesssage:(NSString *)msg code:(NSInteger)errorCode {
    return sqr_errorWithCode((int)errorCode, msg);
}

#pragma mark - load asset

- (void)loadAssetValues:(SQRMediaItem *)item complete:(void(^)(AVPlayerItem *item, NSError * error))completeHandle {
    
    NSURL * url = item.currentUrl;
    if ([url isFileURL]) {
        _loadingPlayItem = [AVPlayerItem playerItemWithURL:url];
        
    }else {
        _loadingPlayItem = [AVPlayerItem mc_playerItemWithRemoteURL:url error:nil];
    }
    
    AVAsset * asset = _loadingPlayItem.asset;
    __weak typeof(asset)weakAsset = asset;
    __weak typeof(self)weakSelf = self;
    __weak typeof(_loadingPlayItem) weakPlayItem = _loadingPlayItem;
    
    [asset loadValuesAsynchronouslyForKeys:[self.class assetKeysRequiredToPlay] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if ([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidEndLoading:media:)]) {
                [weakSelf.delegate mediaPlayerDidEndLoading:weakSelf media:item];
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
            
            if (!weakAsset.playable) {
                LOG_E(@"player error: %@", @"audio cannot play");
                
                if (!customeError) {
                    customeError = [weakSelf errorWithMesssage:@"url can not to play" code:kMediaPlayerErrorCodeCannotPlay];
                }
            }
            
            // 如果文件有异常，删除本地缓存文件。排查本地文件带来的播放错误
            if (customeError) {
                [AVPlayerItem mc_removeCacheWithCacheFilePath:weakPlayItem.mc_cacheFilePath];
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
                completeHandle(weakPlayItem, customeError);
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
    if (item == _currentItem) {
        _currentItem = nil;
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
    if (item == _currentItem) {
        _currentItem = nil;
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
    _currentItem = nil;
    [self stop];
    [self.playItemQueue removeAllObjects];
}

- (void)removePreloadAsset {
    [self.loadingPlayItem cancelPendingSeeks];
    [self.player.currentItem cancelPendingSeeks];
    
    AVURLAsset * preAsset = (AVURLAsset *)self.loadingPlayItem.asset;
    AVURLAsset * curAsset = (AVURLAsset *)self.player.currentItem.asset;
    
    Class cacheloaderClass = NSClassFromString(@"SQRPlayerItemCacheLoader");
    if ([preAsset isKindOfClass:[AVURLAsset class]] &&
        preAsset.resourceLoader.delegate &&
        [preAsset.resourceLoader.delegate isKindOfClass:cacheloaderClass])
    {
        [preAsset.resourceLoader.delegate performSelector:@selector(clear)];
    }
    
    if ([curAsset isKindOfClass:[AVURLAsset class]] &&
        curAsset.resourceLoader.delegate &&
        [curAsset.resourceLoader.delegate isKindOfClass:cacheloaderClass])
    {
        [curAsset.resourceLoader.delegate performSelector:@selector(clear)];
    }
    
    [self.player replaceCurrentItemWithPlayerItem:nil];
}

- (void)prepareToPlay:(SQRMediaItem *)item complete:(PrepareCompleteHandle)completeHandle {
    LOG_I(@"pre load : %@ - %@",item.title,item.currentUrl);
    
    [self stop];
    [self removeObservers];
    [self removeTimeObserver];
    [self removePreloadAsset];
    
    LOG_I(@"pre load cancel : %@",self.loadingPlayItem.mc_URL);
    LOG_I(@"cancel asset: %@",self.loadingPlayItem.asset);
    
    _cacheLoaderCanceled = NO;
    
    if (![self.delegate respondsToSelector:@selector(mediaPlayerWillStartPlaying:media:)] ||
        [self.delegate mediaPlayerWillStartPlaying:self media:item] == NO ||
        !item) {
        if (completeHandle) {
            completeHandle( sqr_errorWithCode(KMediaPlayerErrorCodeLackParamsError, @"check require delegate methed and SQRPlayItem not nil"));
        }
        return;
    }
    
    [self setCurrentState:SQRMediaPlaybackStateLoading];
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerWillStartLoading:media:)]) {
        [self.delegate mediaPlayerWillStartLoading:self media:self.currentItem];
    }
    
    self.currentItem = item;
    self.readyHandle = completeHandle;

    if ([self.delegate respondsToSelector:@selector(mediaPlayerWillStartLoading:media:)]) {
        [self.delegate mediaPlayerWillStartLoading:self media:self.currentItem];
    }
    // 防止连续点击
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadAssetIfNecessary) object:nil];
    [self performSelector:@selector(loadAssetIfNecessary) withObject:nil afterDelay:1.0];
}

- (void)loadAssetIfNecessary {
    [self removeObservers];
    [self removeTimeObserver];
    [self removePreloadAsset];
    
    NSURL * url = self.currentItem.currentUrl;
    if ([url isFileURL]) {
        self.loadingPlayItem = [AVPlayerItem playerItemWithURL:url];
    }else {
        self.loadingPlayItem = [AVPlayerItem mc_playerItemWithRemoteURL:url error:nil];
        [AVPlayerItem removeExpireFiles:self.cacheMaxCount beforeTime:self.expireTime];
    }
    
    __weak AVAsset *weakAsset = self.loadingPlayItem.asset;
    __weak typeof(self)weakSelf = self;
    __weak AVPlayerItem * weakPlayItem = self.loadingPlayItem;
    
    LOG_I(@"load asset: %@",self.loadingPlayItem.asset);
    
    [self.loadingPlayItem.asset loadValuesAsynchronouslyForKeys:[self.class assetKeysRequiredToPlay] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            
            LOG_I(@"finish load asset: %@",weakAsset);

            if ([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidEndLoading:media:)]) {
                [weakSelf.delegate mediaPlayerDidEndLoading:weakSelf media:weakSelf.currentItem];
            }
            
            NSArray * allKeys = [weakSelf.class assetKeysRequiredToPlay];
            
            NSError * customeError = nil;
            for (NSString * key in allKeys) {
                NSError * error = nil;
                if ([weakAsset statusOfValueForKey:key error:&error] != AVKeyValueStatusLoaded && error) {
                    LOG_E(@"player error: %@", error);
                    customeError = error;
                    break;
                }
            }
            // 如果文件有异常，删除本地缓存文件。排查本地文件带来的播放错误
            if (customeError) {
                [AVPlayerItem mc_removeCacheWithCacheFilePath:weakSelf.player.currentItem.mc_cacheFilePath];
            }
            // 递归多个url，寻找可播放url
            if (customeError && [weakSelf.currentItem retryNext]) {
                if ([weakSelf.delegate respondsToSelector:@selector(mediaPlayerRetryNext:error:media:)]) {
                    [weakSelf.delegate mediaPlayerRetryNext:weakSelf error:customeError media:weakSelf.currentItem];
                }
                [weakSelf loadAssetIfNecessary];
                return;
            }
            
            if (customeError) {
                if([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidFailedWithError:player:media:)]) {
                    [weakSelf.delegate mediaPlayerDidFailedWithError:customeError player:weakSelf media:weakSelf.currentItem];
                }
            }else {
                weakPlayItem.assetLoaded = YES;
                [weakSelf.player replaceCurrentItemWithPlayerItem:weakPlayItem];
                [weakSelf addObserves];
                [weakSelf addTimeObserver];
                
                if (weakSelf.readyHandle && weakSelf.player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
                    weakSelf.readyHandle(nil);
                    weakSelf.readyHandle = nil;
                }
                
                if ([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidEndLoading:media:)]) {
                    [weakSelf.delegate mediaPlayerDidEndLoading:weakSelf media:weakSelf.currentItem];
                }
                
                
#ifdef SQRPlayerTestSuspended
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [weakSelf cancelRequests];
                });
#endif
            }
        });
    }];
}

- (void)cancelRequests {
    _cacheLoaderCanceled = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:SQRCancelOrResumeAllRequestNotification object:self userInfo:@{@"cancel":@(YES)}];
#ifdef SQRPlayerTestSuspended
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self resumeRequests];
    });
#endif
}

- (void)resumeRequests {
    _cacheLoaderCanceled = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:SQRCancelOrResumeAllRequestNotification object:self userInfo:@{@"cancel":@(NO)}];
}

- (BOOL)bufferCompleteWithUrl:(NSURL *)url {
    AVPlayerItem * item = [AVPlayerItem mc_playerItemWithRemoteURL:url error:nil];
    if (!item) {
        return NO;
    }
    SQRPlayerItemCacheFile * cacheFile = [SQRPlayerItemCacheFile cacheFileWithFilePath:item.mc_cacheFilePath];
    if (!cacheFile) {
        return NO;
    }
    
    return cacheFile.isCompeleted;
}

-(void)playMedia:(SQRMediaItem *)item {
    __weak typeof(self)weakSelf = self;

    [self prepareToPlay:item complete:^( NSError *error) {
        if (error) {
        }else {
            [weakSelf play];
        }
    }];
}

- (void)playNextItem {
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidSFinishPlaying:media:)]) {
        [self.delegate mediaPlayerDidSFinishPlaying:self media:_currentItem];
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
        [self pause];
    }
}

- (void)playPreviouseItem {
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidSFinishPlaying:media:)]) {
        [self.delegate mediaPlayerDidSFinishPlaying:self media:_currentItem];
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

- (SQRMediaItem *)currentItem {
    return _currentItem;
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
    if (_cacheLoaderCanceled) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SQRCancelOrResumeAllRequestNotification object:self userInfo:@{@"cancel":@(NO)}];
        _cacheLoaderCanceled = NO;
    }
    
    if (self.playbackState == SQRMediaPlaybackStateStopped) {
        [self.player seekToTime:CMTimeMake(0, 1)];
    }
    if (self.currentItem == nil) {
        if (self.playItemQueue && _playingIndex < self.playItemQueue.count) {
            [self playMedia:self.playItemQueue[_playingIndex]];
        }else {
            [self playMedia:self.playItemQueue.firstObject];
        }
    }
    else {
        [self.player play];
    }
    
    [self setCurrentState:SQRMediaPlaybackStatePlaying];
    
    [self startCheckTimer];
}

- (void)startCheckTimer {
    [self checkResourcesIsReady];
    
    [self stopCheckTimer];
    self.checkTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(checkResourcesIsReady) userInfo:nil
                                                      repeats:YES];
}

- (void)stopCheckTimer {
    [self.checkTimer invalidate];
    self.checkTimer = nil;
}

- (void)checkResourcesIsReady {
    [self tryToPlayIfStalled];
}

static int emptyBufferRetryCount = 0;

- (void)tryToPlayIfStalled {
    if (!self.player.currentItem) {
        if ([self.delegate respondsToSelector:@selector(mediaPlayerIsBuffering:isBuffering:)]) {
            [self.delegate mediaPlayerIsBuffering:self isBuffering:YES];
        }
        return;
    }
    
    if (!_isStalled || !self.player.currentItem.assetLoaded) {
        if ([self.delegate respondsToSelector:@selector(mediaPlayerIsBuffering:isBuffering:)]) {
            [self.delegate mediaPlayerIsBuffering:self isBuffering:_isStalled];
        }
        if (self.playbackState == SQRMediaPlaybackStatePlaying && self.player.rate <= 0) {
            [self.player play];
        }
        return;
    }
   
    LOG_E(@"player is stalled,retrying play..",nil);
    
    
    if (self.player.currentItem.isPlaybackLikelyToKeepUp ||
        [self timeBuffered] > [self currentPlaybackTime] + 5) {
        _isStalled = NO;
        emptyBufferRetryCount = 0;
        [self.player play];
    }
    if (_isStalled) {
        if (emptyBufferRetryCount>10) {
            NSTimeInterval curTime = [self currentPlaybackTime];
            curTime = MAX((curTime - 1),0);
            LOG_I(@"重试次数超过10次，返回到上一秒 : %f",curTime);
            [self seekTo:curTime];
            emptyBufferRetryCount = 0;
        }
        emptyBufferRetryCount++;
    }
    if ([self.delegate respondsToSelector:@selector(mediaPlayerIsBuffering:isBuffering:)]) {
        [self.delegate mediaPlayerIsBuffering:self isBuffering:_isStalled];
    }
}



- (NSTimeInterval)timeBuffered
{
    CMTimeRange timeRange = [[self.player.currentItem.loadedTimeRanges lastObject] CMTimeRangeValue];
    return CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration);
}

- (void)pause {
    [self stopCheckTimer];
    
    if (!self.player.currentItem) {
        return;
    }
    
    [self.player pause];
    [self setCurrentState:SQRMediaPlaybackStatePaused];
}

- (void)stop {
    [self removeObservers];
    [self stopCheckTimer];
    [self removePreloadAsset];
    
    if (self.playbackState == SQRMediaPlaybackStateStopped) {
        return;
    }
    [self.player pause];
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerDidStop:media:)]) {
        [self.delegate mediaPlayerDidStop:self media:_currentItem];
    }
    
    [self setCurrentState:SQRMediaPlaybackStateStopped];
}

- (void)clear
{
    [self stop];
    [self removeTimeObserver];
    [self removePreloadAsset];
    
    @try {
        [_player removeObserver:self forKeyPath:@"status"];
        [_player removeObserver:self forKeyPath:kSQRPlayRateKeyPath];
    } @catch(NSException *exception) {
    }
    
    [self removePlayItemNotifcation];
    [self removeObservers];
    
    [self.player pause];
    
    [self.checkTimer invalidate];
    self.checkTimer = nil;
}

-(void)seekTo:(NSTimeInterval)time {
    __weak typeof(self)weakSelf = self;
    
    self.seeking = YES;
    [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        weakSelf.seeking = NO;
    }];
    
    // 一秒后打开seeking的状态
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        weakSelf.seeking = NO;
        [weakSelf updatLockScreenInfo:_currentItem];
    });
}

- (void)refreshLockInfo:(SQRMediaItem *)item {
    [self updatLockScreenInfo:item];
}
#pragma mark - Buffering

- (void)startBuffering {
    _buffering = YES;
    
    LOG_I(@"player if buffering",nil);
}

- (void)endBuffering {
    // 恢复继续播放
    if (_buffering || self.player.rate > 0) {
        [self setCurrentState:SQRMediaPlaybackStatePlaying];
        [self play];
    }
    _buffering = NO;
    
    LOG_I(@"player  buffering end",nil);
}

#pragma mark -

- (void)setCurrentState:(SQRMediaPlaybackState)state {
    if (state == _playbackState) {
        return;
    }
    
    if (self.player.status != AVPlayerItemStatusReadyToPlay &&
        state != SQRMediaPlaybackStateLoading )
    {
        state = SQRMediaPlaybackStateStopped;
    }
    
    if ([self.delegate respondsToSelector:@selector(mediaPlayerWillChangeState:state:)]) {
        [self.delegate mediaPlayerWillChangeState:self state:state];
    }
    
    [self removeAudioSessionNotification];

    if (state == SQRMediaPlaybackStatePlaying) {
        
        NSError * error = nil;
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
        [audioSession setActive:YES error:NULL];
        
        [self addAudioSessionNotification];
        //  更新锁屏信息
        [self updatLockScreenInfo:_currentItem];

    }
    
    _playbackState = state;
    
    // log
    LOG_I(@"player statue is %@",[[self class] descriptionForState:state]);
}


- (void)updatLockScreenInfo:(SQRMediaItem *)item {
    if (!item) {
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
        return;
    }
    
    NSMutableDictionary * info = [NSMutableDictionary dictionary];
    [info setObject:item.title ?: @"" forKey:MPMediaItemPropertyTitle];
    [info setObject:@([self currentPlaybackTime]) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [info setObject:@([self currentPlaybackDuration]) forKey:MPMediaItemPropertyPlaybackDuration];
    // 专辑名称
    [info setObject:[item albumTitle] ?: @"" forKey:MPMediaItemPropertyAlbumTitle];
    // 艺术家
    [info setObject:[item artist] ?: @"" forKey:MPMediaItemPropertyArtist];
    
    UIImage * coverImg = [item artworkImage];
    if ([self.delegate respondsToSelector:@selector(mediaPlayerArtworkImage:media:)]) {
        coverImg = [self.delegate mediaPlayerArtworkImage:self media:_currentItem];
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

- (void)recieveInvalidResponse:(NSNotification *)notification {
    [self playerFailedToEnd:notification];
}

- (void)addObserves {
    [self removeObservers];
    
    [self addPlayerItemObservers];
}

- (void)removeObservers {
    [self removePlayerItemObservers];
}


- (void)addPlayerItemObservers {
    if (!self.player.currentItem) {
        return;
    }
    @try {
        [self.player.currentItem addObserver:self forKeyPath:kSQRLoadedTimeRangesKeyPath options:NSKeyValueObservingOptionNew context:&kSQRAudioControllerBufferingObservationContext];
        [self.player.currentItem addObserver:self forKeyPath:kSQRPlayItemBufferStateKeyPath options:NSKeyValueObservingOptionNew context:&kSQRAudioControllerPlayItemBufferObservationContext];
        [self.player.currentItem addObserver:self forKeyPath:kSQRPlayItemLikeToKeepupKeyPath options:NSKeyValueObservingOptionNew context:kSQRAudioControllerPlayItemLikeKeeyupObservationContext];
        [self.player.currentItem addObserver:self forKeyPath:kSQRPlayItemStatusKeyPath options:NSKeyValueObservingOptionNew context:kSQRAudioControllerPlayItemStatusObservationContext];
    } @catch (NSException *exception) {
         LOG_E(@"%@",@"[player error] add observer failed");
    } @finally {
        
    }
}
- (void)removePlayerItemObservers {
    @try {
        [self.player.currentItem removeObserver:self forKeyPath:kSQRLoadedTimeRangesKeyPath];
        [self.player.currentItem removeObserver:self forKeyPath:kSQRPlayItemBufferStateKeyPath];
        [self.player.currentItem removeObserver:self forKeyPath:kSQRPlayItemLikeToKeepupKeyPath];
        [self.player.currentItem removeObserver:self forKeyPath:kSQRPlayItemStatusKeyPath];
    } @catch(NSException *exception) {
        LOG_E(@"%@",@"[player error] remove observer failed");
    }
    
}

-(void)addTimeObserver {
    [self removeTimeObserver];
    
    __weak typeof(self)weakSefl = self;
    if (!_timeObserver) {
        _timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [weakSefl syncPlayProcess:time];
        }];
    }
}

- (void)removeTimeObserver {
    if (_timeObserver) {
        [self.player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
}

- (void)addPlayItemNotifcation {
    
    [self removePlayItemNotifcation];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playitemPlayDidStalled:) name:AVPlayerItemPlaybackStalledNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerFailedToEnd:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
}


- (void)removePlayItemNotifcation {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:nil];
     [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
}

- (void)addAudioSessionNotification {
    [self removeAudioSessionNotification];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterrupted:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionChangeRoute:) name:AVAudioSessionRouteChangeNotification object:nil];
}

- (void)removeAudioSessionNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
}

#pragma mark - 音频打断 | 切换

- (void)audioSessionInterrupted:(NSNotification *)notification {
    NSNumber *interruptionType = [[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey];
    AVAudioSessionInterruptionType type = interruptionType.unsignedIntegerValue;
    NSNumber* secondReason = [[notification userInfo] objectForKey:AVAudioSessionInterruptionOptionKey] ;
    
    BOOL resume = NO;
    switch ([secondReason integerValue]) {
        case AVAudioSessionInterruptionOptionShouldResume: {
            resume = YES;
        }
            break;
    }
    if ([_delegate respondsToSelector:@selector(mediaPlayerDidInterrupt:interruptState:resume:)]) {
        [_delegate mediaPlayerDidInterrupt:self interruptState:type resume:resume];
    }
}

- (void)audioSessionChangeRoute:(NSNotification *)notification {
    NSDictionary *dic=notification.userInfo;
    int changeReason= [dic[AVAudioSessionRouteChangeReasonKey] intValue];
    
    if (changeReason==AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        [self pause];

        if (![AVAudioSession sharedInstance].currentRoute.outputs) {
            NSLog(@"切换到扬声器，音乐暂停");
        }
        if([_delegate respondsToSelector:@selector(mediaPlayerDidChangeAudioRoute:)]) {
            [_delegate mediaPlayerDidChangeAudioRoute:self];
        }
    }
}

#pragma mark - 结束处理
- (void)playerItemDidReachEnd:(NSNotification *)notification {
    AVPlayerItem * item = notification.object;
    NSTimeInterval isOver = [self currentPlaybackDuration] - [self currentPlaybackTime];
    
    if (self.player.currentItem == item && isOver < 5 /*至少距离播放结束还有5秒才播放下一首*/) {
        [self playNextItem];
    }
}


- (void)playitemPlayDidStalled:(NSNotification *)notification {
    _isStalled = YES;
}


- (void)playerFailedToEnd:(NSNotification *)notification {
    NSError * error = [notification.userInfo objectForKey:AVPlayerItemFailedToPlayToEndTimeErrorKey];
    LOG_E(@"player cannot to end: %@",error);
    if (error && [self.delegate respondsToSelector:@selector(mediaPlayerDidFailedWithError:player:media:)] && self.playbackState != SQRMediaPlaybackStateStopped) {
        [AVPlayerItem mc_removeCacheWithCacheFilePath:self.player.currentItem.mc_cacheFilePath];
        
        [self.delegate mediaPlayerDidFailedWithError:error player:self media:_currentItem];
        [self stop];
        return;
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
    
    if (context == kSQRAudioControllerPlayItemStatusObservationContext && [keyPath isEqualToString:kSQRPlayItemStatusKeyPath])
    {
        AVPlayerItem * item = (AVPlayerItem *)object;
        if (item.status == AVPlayerItemStatusReadyToPlay) {
            LOG_I(@"AVPlayerItem 已准备好播放",nil);
            if (self.readyHandle) {
                self.readyHandle(nil);
                self.readyHandle = nil;
            }
        }
        else {
            if (self.readyHandle) {
                self.readyHandle(sqr_errorWithCode(kMediaPlayerErrorCodePlayerTimeOut, @"player status is not readyToPlay"));
                self.readyHandle = nil;
            }
        }
        return;
    }
    else if ([keyPath isEqualToString:@"status"] && [object isKindOfClass:[AVPlayer class]]) {
        if (self.player.status == AVPlayerStatusReadyToPlay) {
            
        }else {
            if (self.readyHandle) {
                self.readyHandle(sqr_errorWithCode(kMediaPlayerErrorCodePlayerTimeOut, @"player status is not readyToPlay"));
                self.readyHandle = nil;
            }
        }
        return;
    }
    else if (context == kSQRAudioControllerBufferingObservationContext) {
        AVPlayerItem* playerItem = (AVPlayerItem*)object;
        NSArray* times = playerItem.loadedTimeRanges;
        
        NSValue* value = [times firstObject];
        
        if(value) {
            CMTimeRange range;
            [value getValue:&range];
            float start = CMTimeGetSeconds(range.start);
            float duration = CMTimeGetSeconds(range.duration);
            
            CGFloat videoAvailable = start + duration;
            CGFloat totalDuration = CMTimeGetSeconds(playerItem.asset.duration);
            CGFloat progress = videoAvailable / totalDuration;
            
            __weak typeof(self)weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                if([weakSelf.delegate respondsToSelector:@selector(mediaPlayerDidUpdateBufferProgress:player:media:)]) {
                    [weakSelf.delegate mediaPlayerDidUpdateBufferProgress:progress player:weakSelf media:_currentItem];
                }
            });
        }
        return;
    }
    else if ( context == kSQRAudioControllerPlayStateObservationContext &&
              keyPath == kSQRPlayRateKeyPath)
    {
        NSNumber * rateNumber = change[NSKeyValueChangeNewKey];
        if ([rateNumber isKindOfClass:[NSNumber class]]) {
            
            float rate = [rateNumber floatValue];
            // 暂时不使用监听来判断播放状态
            if (rate == 0.0) {
            }
        }
        return;
    }
    
    else if (context == kSQRAudioControllerPlayItemBufferObservationContext && keyPath == kSQRPlayItemBufferStateKeyPath) {
        /*
        // 播放暂停，无缓存
        if ([self.player.currentItem isPlaybackBufferEmpty] &&
            self.player.rate > 0)
        {
            [self startBuffering];
        }
         */
        return;
    }else if (context == kSQRAudioControllerPlayItemLikeKeeyupObservationContext && keyPath == kSQRPlayItemLikeToKeepupKeyPath) {
        LOG_I(@"Playitem likelyToKeepUp: %@",self.player.currentItem.playbackLikelyToKeepUp ? @"缓冲结束，开始播放":@"缓冲中...");
        /*
        float rate = CMTimebaseGetRate(self.player.currentItem.timebase);
        LOG_I(@"playitem rate: %f",rate);
        if (self.player.currentItem.isPlaybackLikelyToKeepUp) {
            [self endBuffering];
        }else if(self.playbackState != SQRMediaPlaybackStatePaused || self.player.rate > 0) {
            [self startBuffering];
        }
         */
        return;
    }
    
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// 尝试加载对应key的内容
+ (NSArray *)assetKeysRequiredToPlay {
    return @[@"playable",@"tracks",@"duration"];
}

- (void)syncPlayProcess:(CMTime)time {
    //如果正在播放，刷新进度
    if (_seeking == NO &&[self.delegate respondsToSelector:@selector(mediaPlayerDidChangedPlaybackTime:)] && self.player.status == AVPlayerStatusReadyToPlay) {
        [self.delegate mediaPlayerDidChangedPlaybackTime:self];
    }
}
@end


#pragma mark  - 类目 -


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

@implementation SQRPlayer (Logger)

+ (NSString *)descriptionForState:(SQRMediaPlaybackState)state {
    NSString * des = @"";
    switch (state) {
        case SQRMediaPlaybackStatePaused:
            des = @"暂停";
            break;
        case SQRMediaPlaybackStateLoading:
            des =  @"加载中";
            break;
        case SQRMediaPlaybackStatePlaying:
            des =  @"播放中";
            break;
        case SQRMediaPlaybackStateStopped:
            des =  @"停止";
            break;
        default:
            break;
    }
    return des;
}
@end
