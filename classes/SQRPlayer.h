//
//  SQRPlayer.h
//  AVFoundationQueuePlayer-iOS
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SQRMediaItem.h"

@interface SQRPlayer : NSObject
+ (instancetype)sharePlayer;

- (void)play;
- (void)pause;
- (void)stop;

- (void)playMedia:(SQRMediaItem *)item;
- (void)seekTo:(NSTimeInterval)time;
@end
