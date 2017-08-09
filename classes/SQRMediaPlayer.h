//
//  SQRMediaPlayer.h
//  SQRAudioPlayerDemo
//
//  Created by huanwh on 2017/8/4.
//  Copyright © 2017年 wally.h. All rights reserved.
//

#ifndef SQRMediaPlayer_h
#define SQRMediaPlayer_h


#ifdef SQRPlayer_LOG

#define INFO_FMT(fmt) [NSString stringWithFormat:@"[PLAYER INFO] %s(%d) %@", \
__PRETTY_FUNCTION__, \
__LINE__, \
fmt]

#define ERROR_FMT(fmt) [NSString stringWithFormat:@"[PLAYER ERROR] %s(%d) %@", \
__PRETTY_FUNCTION__, \
__LINE__, \
fmt]


#define LOG_I(fmt,...) NSLog(INFO_FMT(fmt),##__VA_ARGS__)
#define LOG_E(fmt,...) NSLog(ERROR_FMT(fmt),##__VA_ARGS__)

#else

#define LOG_I(fmt,...)
#define LOG_E(fmt,...)

#endif



#define kMediaPlayerErrorCodeCannotPlay -1000    // 源不能播放
#define kMediaPlayerErrorCodePlayerTimeOut -1001 // 播放器超时

#endif




