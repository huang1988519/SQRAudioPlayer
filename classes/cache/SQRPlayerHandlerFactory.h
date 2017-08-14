//
//  SQRPlayerHandlerFactory.h
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2017/8/10.
//  Copyright © 2017年 wally.h. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SQRPlayerHandlerFactory : NSObject

/**
 注册对应协议的处理者

 @param handler 处理者
 @param protocol 协议名称
 */
+ (void)resisterHandler:(id)handler protocol:(Protocol *)protocol;


/**
 返回对应协议的处理者

 @param protocol 协议名称
 */
+ (id)hanlerForProtocol:(Protocol *)protocol;
@end
