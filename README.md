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
    item.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group30/M03/6C/8E/wKgJXll58uDQ-lJnABJ__ybdmiw564.m4a"];
    [_player playMedia:item];
```

添加队列
```
 SQRMediaItem * item1 = [SQRMediaItem new];
    item1.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group7/M0B/1B/CE/wKgDWlV2iSWwdkEQAEuBnDfPtxw914.m4a"];
    
    SQRMediaItem * item2 = [SQRMediaItem new];
    item2.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group12/M00/1C/AD/wKgDW1V39AfDOSDwAE7IowCHNWQ865.m4a"];
    
    SQRMediaItem * item3 = [SQRMediaItem new];
    item3.assetUrl = [NSURL URLWithString:@"http://audio.xmcdn.com/group11/M03/1D/EF/wKgDbVV5B3bjxcFCAFLbZMLGZbg032.m4a"];
    
    [_player setQueue:@[item1,item2,item3]];
```

快进
```
if ([_player playbackState] == SQRMediaPlaybackStatePlaying) {
        
        float offset = slider.value * [_player currentPlaybackDuration];
        [_player seekTo:offset];
    }
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

```
