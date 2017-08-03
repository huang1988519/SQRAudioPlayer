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
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _player = [SQRPlayer sharePlayer];
}

- (IBAction)playTest:(id)sender {
    SQRMediaItem * item = [SQRMediaItem new];
    item.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group30/M03/6C/8E/wKgJXll58uDQ-lJnABJ__ybdmiw564.m4a"];
    [_player playMedia:item];
    _player.delegate = self;
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

#pragma mark -
-(BOOL)mediaPlayerWillStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    return YES;
}

-(void)mediaPlayerDidUpdateBufferProgress:(float)progress player:(SQRPlayer *)player media:(SQRMediaItem *)item {
    NSLog(@"[demo] play buffer progress: %0.2f",progress);
}

- (void)mediaPlayerDidStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    NSLog(@"[demo] player is playing: %@",item.assetUrl.absoluteString);
}
@end
