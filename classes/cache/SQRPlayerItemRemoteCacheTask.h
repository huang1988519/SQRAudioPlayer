
//
//  Created by huanwh on 2017/7/31.

//

#import "SQRPlayerItemCacheTask.h"

@interface SQRPlayerItemRemoteCacheTask : SQRPlayerItemCacheTask
<NSURLSessionDataDelegate>

@property (nonatomic,strong) NSOperationQueue *sessionQueue;
@property (nonatomic,strong) NSHTTPURLResponse  *response;
@end
