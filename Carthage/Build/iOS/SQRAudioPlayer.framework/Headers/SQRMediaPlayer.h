//
//  SQRMediaPlayer.h
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2017/8/4.
//  Copyright © 2017年 wally.h. All rights reserved.
//

#ifdef SQRPlayer_LOG

#ifndef NSLog
#define NSLog(FORMAT, ...) fprintf(stderr,"-- %s:%d\n\t%s\n\n",[[[NSString stringWithUTF8String:__FILE__] lastPathComponent] UTF8String], __LINE__, [[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);
#endif

#define INFO_FMT(fmt) [NSString stringWithFormat:@"[PLAYER INFO]%@", \
fmt]

#define ERROR_FMT(fmt) [NSString stringWithFormat:@"[PLAYER ERROR] %@", \
fmt]


#define LOG_I(fmt,...) NSLog(INFO_FMT(fmt),##__VA_ARGS__)
#define LOG_E(fmt,...) NSLog(ERROR_FMT(fmt),##__VA_ARGS__)

#else

#define LOG_I(fmt,...)
#define LOG_E(fmt,...)

#endif

//#define SQRPlayerTestSuspended


///关闭所有正在请求的 播放器请求
FOUNDATION_EXPORT NSString * const SQRCancelOrResumeAllRequestNotification;
///远程地址返回reponse 不是音频格式
FOUNDATION_EXPORT NSString * const SQRRemoteResponseIsNotAudioNotification;


#define kMediaPlayerErrorCodeCannotPlay -1111800        // 源不能播放
#define kMediaPlayerErrorCodePlayerTimeOut -1111801     // 播放器超时
#define KMediaPlayerErrorCodeNotAllowNetwork -1111802   // 禁止访问网络
#define KMediaPlayerErrorCodeTaskCanceled -1111803      // 任务被取消
#define KMediaPlayerErrorCodeResourceTypeError -1111804 // 资源文件类型错误
#define KMediaPlayerErrorCodeLackParamsError -1111805   // 缺少必要的配置信息

#import "SQRPlayer.h"
#import "SQRMediaItem.h"


NS_INLINE NSError *sqr_errorWithCode(int errorCode, NSString *reason)
{
    return [NSError errorWithDomain:@"ios.sqrrader.com" code:errorCode userInfo:@{
                                                                                         NSLocalizedDescriptionKey : @"The operation couldn’t be completed.",
                                                                                         NSLocalizedFailureReasonErrorKey : reason,
                                                                                         }];
}





@protocol SQRPlayerNetworkChangedProtocol <NSObject>

@required
/**
 Whether or not player allowed access network。default is YES;
 *  NO 所有需要使用网络的数据段均失败。
 *  YES  播放器会请求网络完成预加载

 @param url 当前需要使用网络的url
 @return 是否允许使用网络
 */
- (BOOL)mediaPlayerCanUseNetwork:(NSURL *)url;

@end


