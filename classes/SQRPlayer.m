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


@interface SQRPlayer()
{
    id<NSObject>_timeObserver;
}
@property (nonatomic, strong)AVQueuePlayer * player;
@property (nonatomic, strong)SQRMediaItem  * currentPlayItem;
@end

@implementation SQRPlayer

static int SQRPlayerViewControllerKVOContext = 0;

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
        __weak typeof(self)weakSelf = self;
        
        _player = [[AVQueuePlayer alloc] init];
        _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [weakSelf syncPlayProcess:time];
        }];
        [self addObservers];
    }
    return self;
}

-(void)dealloc {
    if (_timeObserver) {
        [self.player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
    
    [self.player pause];
    
    [self removeObserver:self forKeyPath:@"player.currentItem.duration" context:&SQRPlayerViewControllerKVOContext];
    [self removeObserver:self forKeyPath:@"player.rate" context:&SQRPlayerViewControllerKVOContext];
    [self removeObserver:self forKeyPath:@"player.currentItem.status" context:&SQRPlayerViewControllerKVOContext];
    [self removeObserver:self forKeyPath:@"player.currentItem" context:&SQRPlayerViewControllerKVOContext];
}

- (void)addObservers {
    /*
    刷新UI变化
     */
    [self addObserver:self forKeyPath:@"player.currentItem.duration" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:&SQRPlayerViewControllerKVOContext];
    [self addObserver:self forKeyPath:@"player.rate" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:&SQRPlayerViewControllerKVOContext];
    [self addObserver:self forKeyPath:@"player.currentItem.status" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:&SQRPlayerViewControllerKVOContext];
    [self addObserver:self forKeyPath:@"player.currentItem" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:&SQRPlayerViewControllerKVOContext];
}

- (void)loadAssetValues:(SQRMediaItem *)item {
    AVURLAsset * asset = [AVURLAsset URLAssetWithURL:item.assetUrl options:nil];
    
    __weak AVURLAsset * weakAsset = asset;
    __weak typeof(self)weakSelf = self;
    [asset loadValuesAsynchronouslyForKeys:[self.class assetKeysRequiredToPlay] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray * allKeys = [self.class assetKeysRequiredToPlay];
            
            for (NSString * key in allKeys) {
                NSError * error = nil;
                if ([asset statusOfValueForKey:key error:&error] == AVKeyValueStatusFailed) {
                    NSLog(@"player error: %@", error);
                    return;
                }
            }
            
            if (!asset.playable || asset.hasProtectedContent) {
                NSLog(@"player error: %@", @"audio cannot play");
                return;
            }
            
            NSError *error = nil;
            AVPlayerItem * item = [AVPlayerItem mc_playerItemWithRemoteURL:[weakAsset URL] error:&error];
            if (error) {
                NSLog(@"[sqrplayer error] cache failed");
            }else {
                [item.asset loadValuesAsynchronouslyForKeys:[self.class assetKeysRequiredToPlay] completionHandler:^{
                    [weakSelf.player replaceCurrentItemWithPlayerItem:item];
                    [weakSelf.player play];
                }];
            }
        });
    }];
}
#pragma mark - play & stop & pause
-(void)playMedia:(SQRMediaItem *)item {
    _currentPlayItem = item;
    
    [self loadAssetValues:item];
}

- (void)play {
    [self.player play];
}
- (void)pause {
    [self.player pause];
}
- (void)stop {
    [self.player pause];
}

-(void)seekTo:(NSTimeInterval)time {
    [self.player seekToTime:CMTimeMake(time, 1)];
}
#pragma mark -  Observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != &SQRPlayerViewControllerKVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    // 当前播放item更换
    if ([keyPath isEqualToString:@"player.currentItem"]) {
        
    }
    // 播放offset 更新
    else if ([keyPath isEqualToString:@"player.currentItem.duration"]) {
        
    }
    // 播放速率更新
    else if ([keyPath isEqualToString:@"player.rate"]) {
        
    }
    // 播放状态改变
    else if([keyPath isEqualToString:@"player.currentItem.status"]) {
        if (self.player.currentItem.error) {
            // 播放错误
        }else {
            
        }
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

// 尝试加载对应key的内容
+ (NSArray *)assetKeysRequiredToPlay {
    return @[@"playable", @"hasProtectedContent"];
}

- (void)syncPlayProcess:(CMTime)time {
    //如果正在播放，刷新进度
}
@end
