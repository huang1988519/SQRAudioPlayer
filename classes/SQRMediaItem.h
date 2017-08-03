//
//  SQRMediaItem.h
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 Apple Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SQRMediaItem : NSObject
@property (nonatomic, strong) NSURL * assetUrl;      // 媒体资源地址
@property (nonatomic, strong) NSString * title;      // 媒体名称
@property (nonatomic, strong) NSString * artist;     // 作家
@property (nonatomic, strong) NSString * albumTitle; // 专辑名称
@property (nonatomic, strong) UIImage * artworkImage;// 锁屏封面
@end
