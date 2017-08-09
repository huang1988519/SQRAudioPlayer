//
//  ViewController.m
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 wally.h. All rights reserved.
//

#import "ViewController.h"
#import "SQRPlayer.h"
#import "SQRMediaPlayer.h"
#import <MediaPlayer/MediaPlayer.h>


@interface ViewController ()<SQRMediaPlayerDelegate>
{
    SQRPlayer * _player;
}
@property (weak, nonatomic) IBOutlet UISlider *slider;
@property (weak, nonatomic) IBOutlet UIProgressView *progress;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _player = [SQRPlayer sharePlayer];
    _player.delegate = self;
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




- (IBAction)playTest:(id)sender {
    SQRMediaItem * item = [SQRMediaItem new];
    item.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group30/M03/6C/8E/wKgJXll58uDQ-lJnABJ__ybdmiw564.m4a"]];
    item.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group8/M08/1C/A3/wKgDYVV3xTizBpzwAEvysDE32Lk219.m4a"]];
    
    [_player prepareToPlay:item complete:^(AVPlayerItem *avitem, NSError *error) {
        [_player seekTo:400];
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
    
    SQRMediaItem * item2 = [SQRMediaItem new];
    item2.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group12/M00/1C/AD/wKgDW1V39AfDOSDwAE7IowCHNWQ865.m4a"]];
    
    SQRMediaItem * item3 = [SQRMediaItem new];
    item3.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group8/M08/1C/A3/wKgDYVV3xTizBpzwAEvysDE32Lk219.m4a"]];
    
    SQRMediaItem * item4 = [SQRMediaItem new];
    item4.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group7/M09/2D/65/wKgDWlWKSmOB3Sd6AFOahV91Rwo643.m4a"]];
    
    
    /*
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths objectAtIndex:0];
    NSString *localPath = [docDir stringByAppendingPathComponent:@"1.m4a"];
    */
    NSString * localPath = [[NSBundle mainBundle] pathForResource:@"1" ofType:@"m4a"];
    SQRMediaItem * item5 = [SQRMediaItem new];
    item5.assetUrls = @[[NSURL fileURLWithPath:localPath]];
    
    [_player setQueue:@[item5,item1,item2,item3,item4]];
}
- (IBAction)seekTo:(UISlider *)slider {
    if ([_player playbackState] == SQRMediaPlaybackStatePlaying) {
        
        float offset = slider.value * [_player currentPlaybackDuration];
        [_player seekTo:offset];
    }
}

#pragma mark - delegate

-(BOOL)mediaPlayerWillStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    return YES;
}

-(void)mediaPlayerDidUpdateBufferProgress:(float)progress player:(SQRPlayer *)player media:(SQRMediaItem *)item {
//    LOG_I(@"play buffer progress: %0.2f",progress);
    [self.progress setProgress:progress];
}

- (void)mediaPlayerDidStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    LOG_I(@"player is playing: %@",[item currentUrl].absoluteString);
}

- (void)mediaPlayerDidChangedPlaybackTime:(SQRPlayer *)player {
    float progress = [player currentPlaybackTime] / [player currentPlaybackDuration];
    
    if (!_slider.isTracking) {
        [_slider setValue:progress animated:YES];
    }
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
