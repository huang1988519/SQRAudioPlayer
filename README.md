# SQRAudioPlayer
音乐播放器，包含边播边下载，从缓存播放等等


Usage
---

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
