//
//  ViewController.m
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 wally.h. All rights reserved.
//

#import "ViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import "SQRMediaPlayer.h"

@interface ViewController ()<SQRMediaPlayerDelegate,SQRPlayerNetworkChangedProtocol>
{
    SQRPlayer * _player;
}
@property (weak, nonatomic) IBOutlet UISlider *slider;
@property (weak, nonatomic) IBOutlet UIProgressView *progress;

@property (weak, nonatomic) IBOutlet UILabel *playTimeLabel;
@property (weak, nonatomic) IBOutlet UILabel *cachingTimeLabel;
@property (weak, nonatomic) IBOutlet UILabel *playingName;
@property (weak, nonatomic) IBOutlet UILabel *progressLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _player = [SQRPlayer sharePlayer];
    _player.delegate = self;
    
    [SQRPlayer registHandler:self protocol:@protocol(SQRPlayerNetworkChangedProtocol)];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // 设置音乐后台播放
    [self becomeFirstResponder];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self observeRemoteControl];
}

-(void)viewDidDisappear:(BOOL)animated {
    [self resignFirstResponder];
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [self removeObserveRemoteControl];
    
    [super viewDidDisappear:animated];
}

// 测试地址容易失效，请填入最新地址。
- (IBAction)playTest:(id)sender {
    SQRMediaItem * item = [SQRMediaItem new];
    item.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group7/M0B/1B/CE/wKgDWlV2iSWwdkEQAEuBnDfPtxw914.m4a"]];
    item.assetUrls = @[[NSURL URLWithString:@"http://101.96.10.45/yst8-service.iphone2030.com/downloads/0/4/4/0446d29a9ebfede8f3ceaf9edc81a767.mp3"]];
    
    [_player prepareToPlay:item complete:^( NSError *error) {
//        [_player seekTo:400];
        [_player play];
    }];
}

- (IBAction)previous:(id)sender {
    [_player playPreviouseItem];
}


- (IBAction)next:(id)sender {
    [_player playNextItem];
}


- (IBAction)playOrPause:(id)sender {
    if ([_player playbackState] == SQRMediaPlaybackStatePlaying) {
        [_player pause];
    }else {
        [_player play];
    }
}

- (IBAction)setupQueue:(id)sender {
    SQRMediaItem * item1 = [SQRMediaItem new];
    item1.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group7/M0B/1B/CE/wKgDWlV2iSWwdkEQAEuBnDfPtxw914.m4a"]];
    item1.title = @"音频1";
    
    SQRMediaItem * item2 = [SQRMediaItem new];
    item2.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group30/M02/42/79/wKgJXll4mDbAlqfhAZTHUm3r6Mk310.m4a"]];
    item2.title = @"音频2";
    
    SQRMediaItem * item3 = [SQRMediaItem new];
    item3.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group31/M05/C9/A9/wKgJSVmLhF_g1zP9AB9anbI6d1k907.m4a"]];
    item3.title = @"音频3";
    
    SQRMediaItem * item4 = [SQRMediaItem new];
    item4.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group31/M05/76/FD/wKgJSVmHl0Hw6WQVACLDoYiU2h0159.m4a"]];
    item4.title = @"音频4";

    NSString * localPath = [[NSBundle mainBundle] pathForResource:@"1" ofType:@"m4a"];
    SQRMediaItem * item5 = [SQRMediaItem new];
    item5.assetUrls = @[[NSURL fileURLWithPath:localPath]];
    item5.title = @"本地音频";
    
    [_player setQueue:@[item5,item1,item2,item3,item4]];
}
- (IBAction)seekTo:(UISlider *)slider {
    float offset = slider.value * [_player currentPlaybackDuration];
    [_player seekTo:offset];
}

#pragma mark - delegate

-(BOOL)mediaPlayerWillStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    self.playingName.text = [NSString stringWithFormat:@"%@",item.title];
    return YES;
}

-(void)mediaPlayerDidUpdateBufferProgress:(float)progress player:(SQRPlayer *)player media:(SQRMediaItem *)item {
    
    _cachingTimeLabel.text = [NSString stringWithFormat:@"%0.1lf / %0.1lf",[player currentPlaybackDuration] * progress,[player currentPlaybackDuration]];

    [self.progress setProgress:progress];
}

- (void)mediaPlayerDidStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    LOG_I(@"player is playing: %@",[item currentUrl].absoluteString);
}

- (void)mediaPlayerDidChangedPlaybackTime:(SQRPlayer *)player {
    float progress = [player currentPlaybackTime] / [player currentPlaybackDuration];
    
    _playTimeLabel.text = [NSString stringWithFormat:@"%0.1lf / %0.1lf",[player currentPlaybackTime],[player currentPlaybackDuration]];
    _progressLabel.text = [NSString stringWithFormat:@"%0.1lf / %0.1lf",[player currentPlaybackTime],[player currentPlaybackDuration]];
    
    if (!_slider.isTracking) {
        [_slider setValue:progress animated:YES];
    }
}

-(void)mediaPlayerWillChangeState:(SQRPlayer *)player state:(SQRMediaPlaybackState)state {
    LOG_E(@"播放器 will ChangeState %d ",state);
}

-(void)mediaPlayerDidFailedWithError:(NSError *)error player:(SQRPlayer *)player media:(SQRMediaItem *)item {
    LOG_E(@"播放器播放失败",nil);
}

#pragma mark - network

-(BOOL)mediaPlayerCanUseNetwork:(NSURL *)url {
    if ([url isEqual:[NSURL URLWithString:@"http://audio.xmcdn.com/group30/M02/42/79/wKgJXll4mDbAlqfhAZTHUm3r6Mk310.m4a"]]) {
        return YES;
    }
    return YES;
}

#pragma mark - remote control
- (void)observeRemoteControl {
    [self removeObserveRemoteControl];
    
    [[MPRemoteCommandCenter sharedCommandCenter].playCommand addTarget:self action:@selector(playOrPause:)];
    [[MPRemoteCommandCenter sharedCommandCenter].pauseCommand addTarget:self action:@selector(playOrPause:)];
    [[MPRemoteCommandCenter sharedCommandCenter].togglePlayPauseCommand addTarget:self action:@selector(playOrPause:)];
    
    [[MPRemoteCommandCenter sharedCommandCenter].nextTrackCommand addTarget:self action:@selector(requireToPlayNextChapter)];
    [[MPRemoteCommandCenter sharedCommandCenter].previousTrackCommand addTarget:self action:@selector(requirToPlayPreviouseChapter)];
}

- (void)removeObserveRemoteControl {
    [[MPRemoteCommandCenter sharedCommandCenter].playCommand removeTarget:self action:@selector(playOrPause:)];
    [[MPRemoteCommandCenter sharedCommandCenter].pauseCommand removeTarget:self action:@selector(playOrPause:)];
    [[MPRemoteCommandCenter sharedCommandCenter].togglePlayPauseCommand removeTarget:self action:@selector(playOrPause:)];
    
    [[MPRemoteCommandCenter sharedCommandCenter].nextTrackCommand removeTarget:self action:@selector(requireToPlayNextChapter)];
    [[MPRemoteCommandCenter sharedCommandCenter].previousTrackCommand removeTarget:self action:@selector(previousTrackCommand)];
}
/// 播放下一章
- (void)requireToPlayNextChapter {
    
}
/// 播放上一章
- (void)requirToPlayPreviouseChapter {
    
}

@end
