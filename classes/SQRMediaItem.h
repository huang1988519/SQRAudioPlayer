//
//  SQRMediaItem.h
//  AVFoundationQueuePlayer-iOS
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 Apple Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SQRMediaItem : NSObject
@property (nonatomic, strong) NSURL * assetUrl;
@property (nonatomic, strong) NSString * title;
@property (nonatomic, strong) NSString * artist;
@property (nonatomic, strong) UIImage * artworkImage;
@end
