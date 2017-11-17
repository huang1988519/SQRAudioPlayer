# SQRAudioPlayer
音乐播放器，包含边播边下载，从缓存播放等等


Usage
---

请求音频资源时，会把播放器请求的数据段拆分为`本地`&`远程`请求放入串行队列。
设置url，开始播放时的步骤为：

### 数据流  
* 播放器请求 0-2 字段，解析音频格式
	* 写入本地
* 播放器请求 0-length(music)
	* 0- length(local)
	* location(local)-length()剩余网络资源)  
		* 写入本地
* 播放器接收音频流开始播放

### 缓存
1. 创建音频空文件 和 音频配置文件http header （.idx）
2. 按照网络请求数据和范围，对本地音频文件进行数据填充，并对音频文件范围进行计算合并。
3. 每次获取本地音频播放时，判断音频是否还在有效期内.


### 使用
初始化
```
_player = [SQRPlayer sharePlayer];
_player.delegate = self;
```

添加单个播放

```
SQRMediaItem * item = [SQRMediaItem new];
    item.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group8/M08/1C/A3/wKgDYVV3xTizBpzwAEvysDE32Lk219.m4a"]];
    [_player playMedia:item];
```

添加队列
```
  SQRMediaItem * item1 = [SQRMediaItem new];
  item1.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group7/M0B/1B/CE/wKgDWlV2iSWwdkEQAEuBnDfPtxw914.m4a"]];

  SQRMediaItem * item2 = [SQRMediaItem new];
  item2.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group12/M00/1C/AD/wKgDW1V39AfDOSDwAE7IowCHNWQ865.m4a"]];

  SQRMediaItem * item3 = [SQRMediaItem new];
  item3.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group8/M08/1C/A3/wKgDYVV3xTizBpzwAEvysDE32Lk219.m4a"]];

  SQRMediaItem * item4 = [SQRMediaItem new];
  item4.assetUrls = @[[NSURL URLWithString:@"http://audio.xmcdn.com/group7/M09/2D/65/wKgDWlWKSmOB3Sd6AFOahV91Rwo643.m4a"]];
```

快进
```
if ([_player playbackState] == SQRMediaPlaybackStatePlaying) {

        float offset = slider.value * [_player currentPlaybackDuration];
        [_player seekTo:offset];
    }
```


设置播放位置并播放

```
[_player prepareToPlay:item complete:^(AVPlayerItem *avitem, NSError *error) {
        [_player seekTo:400];
        [_player play];
    }];
```


代理
```
#pragma mark - delegate

-(BOOL)mediaPlayerWillStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    return YES;
}

-(void)mediaPlayerDidUpdateBufferProgress:(float)progress player:(SQRPlayer *)player media:(SQRMediaItem *)item {
    NSLog(@"[demo] play buffer progress: %0.2f",progress);
    [self.progress setProgress:progress];
}

- (void)mediaPlayerDidStartPlaying:(SQRPlayer *)player media:(SQRMediaItem *)item {
    NSLog(@"[demo] player is playing: %@",item.assetUrl.absoluteString);
}

- (void)mediaPlayerDidChangedPlaybackTime:(SQRPlayer *)player {
    float progress = [player currentPlaybackTime] / [player currentPlaybackDuration];
    [_slider setValue:progress animated:YES];
}

/* 播放被终端。 type 为被中断理由*/
- (void)mediaPlayerDidInterrupt:(SQRPlayer *)player interruptState:(AVAudioSessionInterruptionType)type
{
}

/* 播放输出源变化。 切换到外设时音乐继续播放； 切换到手机扬声器时音乐暂停。*/
- (void)mediaPlayerDidChangeAudioRoute:(SQRPlayer *)player
{
}

/* 设置多个源，播放当前源地址 尝试失败*/
- (void)mediaPlayerRetryNext:(SQRPlayer *)player error:(NSError *)error media:(SQRMediaItem *)item {

}

```
