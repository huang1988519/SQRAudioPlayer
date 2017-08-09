//
//  SQRMediaItem.h
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 Apple Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SQRMediaItem : NSObject
@property (nonatomic, strong) NSArray <NSURL*> * assetUrls;// 媒体资源地址
@property (nonatomic, readonly) NSURL * currentUrl;      // 当前需要播放的URL
@property (nonatomic, readonly) NSUInteger retryIndex; //default is 0. 当前尝试播放的url index
@property (nonatomic, strong) NSString * title;      // 媒体名称
@property (nonatomic, strong) NSString * artist;     // 作家
@property (nonatomic, strong) NSString * albumTitle; // 专辑名称
@property (nonatomic, strong) UIImage * artworkImage;// 锁屏封面

/** 尝试切换到下一个播放源 */
- (BOOL)retryNext;
@end
