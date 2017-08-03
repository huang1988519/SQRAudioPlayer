//
//  ViewController.m
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 wally.h. All rights reserved.
//

#import "ViewController.h"
#import "SQRPlayer.h"

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

- (IBAction)playTest:(id)sender {
    SQRMediaItem * item = [SQRMediaItem new];
    item.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group30/M03/6C/8E/wKgJXll58uDQ-lJnABJ__ybdmiw564.m4a"];
    [_player playMedia:item];
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
    item1.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group7/M0B/1B/CE/wKgDWlV2iSWwdkEQAEuBnDfPtxw914.m4a"];
    
    SQRMediaItem * item2 = [SQRMediaItem new];
    item2.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group12/M00/1C/AD/wKgDW1V39AfDOSDwAE7IowCHNWQ865.m4a"];
    
    SQRMediaItem * item3 = [SQRMediaItem new];
    item3.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group11/M03/1D/EF/wKgDbVV5B3bjxcFCAFLbZMLGZbg032.m4a"];
    
    [_player setQueue:@[item1,item2,item3]];
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
    NSLog(@"[demo] play buffer progress: %0.2f",progress);
    [self.progress setProgress:progress];
}

- (void)mediaPlayerDidStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    NSLog(@"[demo] player is playing: %@",item.assetUrl.absoluteString);
}

- (void)mediaPlayerDidChangedPlaybackTime:(SQRPlayer *)player {
    float progress = [player currentPlaybackTime] / [player currentPlaybackDuration];
    [_slider setValue:progress animated:YES];
}
@end
