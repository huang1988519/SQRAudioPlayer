//
//  SQRMediaItem.m
//  AVFoundationQueuePlayer-iOS
//
//  Created by huanwh on 2017/8/2.
//  Copyright © 2017年 Apple Inc. All rights reserved.
//

#import "SQRMediaItem.h"
#import "SQRMediaPlayer.h"

@interface SQRMediaItem ()
{
    NSUInteger _retryIndex;
    NSURL * _currentURL;
}
@end

@implementation SQRMediaItem

-(instancetype)init {
    self = [super init];
    if (self) {
        _retryIndex = 0;
    }
    return self;
}

-(void)dealloc {
    LOG_I(@"释放 SQRMediaItem",nil);
}

- (BOOL)retryNext {
    if (_retryIndex < _assetUrls.count -1) {
        _retryIndex++;
        return YES;
    }
    return NO;
}

-(NSURL *)currentUrl {
    if (_assetUrls && _retryIndex<_assetUrls.count) {
        return _assetUrls[_retryIndex];
    }
    
    return nil;
}

-(NSUInteger)retryIndex {
    return _retryIndex;
}
@end
