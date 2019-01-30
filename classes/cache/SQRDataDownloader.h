//
//  SQRDataDownloader.h
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2019/1/30.
//  Copyright © 2019 wally.h. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SQRDataDownloaderProtocol <NSObject>
@end

NS_ASSUME_NONNULL_BEGIN

@interface SQRDataDownloader : NSObject
@property (nonatomic, strong) NSMapTable * mapTable;
+ (instancetype)sharedInstance;
- (NSURLSession *)session;

- (void)setObject:(id)anObject forKey:(id)aKey;
@end

NS_ASSUME_NONNULL_END
