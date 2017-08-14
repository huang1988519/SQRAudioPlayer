//
//  SQRPlayerHandlerFactory.m
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2017/8/10.
//  Copyright © 2017年 wally.h. All rights reserved.
//

#import "SQRPlayerHandlerFactory.h"
#import "SQRMediaPlayer.h"


@interface SQRPlayerHandlerFactory()
@property (nonatomic, strong) NSMapTable *handlesTable; //注册的handle

@end

@implementation SQRPlayerHandlerFactory
+ (instancetype)share {
    static SQRPlayerHandlerFactory * _sharInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharInstance = [[self alloc] init];
        _sharInstance.handlesTable = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory];
    });
    
    return _sharInstance;
}

+ (void)resisterHandler:(id)handler protocol:(Protocol *)protocol {
    LOG_I(@"register handler %@",NSStringFromProtocol(protocol));
    NSAssert(handler && protocol, @"handle or protocol cannot be nil");
    
    [[SQRPlayerHandlerFactory share].handlesTable setObject:handler forKey:NSStringFromProtocol(protocol)];
}

+ (id)hanlerForProtocol:(Protocol *)protocol {
    NSAssert(protocol, @"cannot find  handler for nil protocol");
    
    id handler = [[SQRPlayerHandlerFactory share].handlesTable objectForKey:NSStringFromProtocol(protocol)];
    return handler;
}
@end
