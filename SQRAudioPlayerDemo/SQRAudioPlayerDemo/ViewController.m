//
//  ViewController.m
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 wally.h. All rights reserved.
//

#import "ViewController.h"
#import "SQRPlayer.h"

@interface ViewController ()
{
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (IBAction)playTest:(id)sender {
    SQRMediaItem * item = [SQRMediaItem new];
    item.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group30/M03/6C/8E/wKgJXll58uDQ-lJnABJ__ybdmiw564.m4a"];
    SQRPlayer *player = [SQRPlayer sharePlayer];
    [player playMedia:item];
}

@end
