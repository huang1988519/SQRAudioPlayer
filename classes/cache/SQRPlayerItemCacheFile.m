
//  Created by huanwh on 2017/7/31.


#import "SQRPlayerItemCacheFile.h"
#import "SQRCacheSupportUtils.h"
#import "SQRMediaPlayer.h"


const NSString *MCAVPlayerCacheFileZoneKey = @"zone";
const NSString *MCAVPlayerCacheFileSizeKey = @"size";
const NSString *MCAVPlayerCacheFileResponseHeadersKey = @"responseHeaders";

/// 接受数据达到上限之后强制保存进度.
const NSUInteger kForceSynchronousMaxCount = 20;

@interface SQRPlayerItemCacheFile ()
{
@private
    BOOL _compelete;
    /// 接受数据达到上限之后强制保存进度.default is 10
    NSUInteger _recieveMaxCount;
}

@property (atomic, strong)NSMutableArray *ranges;
@property (atomic, strong)NSFileHandle *writeFileHandle;
@property (atomic, strong)NSFileHandle *readFileHandle;
@end

@implementation SQRPlayerItemCacheFile

#pragma mark - init & dealloc
+ (instancetype)cacheFileWithFilePath:(NSString *)filePath
{
    return [[self alloc] initWithFilePath:filePath];
}

- (instancetype)initWithFilePath:(NSString *)filePath
{
    if (!filePath)
    {
        return nil;
    }
    NSLog(@"caching path: %@",filePath);
    
    self = [super init];
    if (self)
    {
        NSString *cacheFilePath = [filePath copy];
        NSString *indexFilePath = [NSString stringWithFormat:@"%@%@",filePath,[[self class] indexFileExtension]];
        
        BOOL cacheFileExist = [[NSFileManager defaultManager] fileExistsAtPath:cacheFilePath];
        BOOL indexFileExist = [[NSFileManager defaultManager] fileExistsAtPath:indexFilePath];
        
        BOOL fileExist = cacheFileExist && indexFileExist;
        if (!fileExist)
        {
            NSString *directory = [cacheFilePath stringByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] fileExistsAtPath:directory])
            {
                [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
            }
            fileExist = [[NSFileManager defaultManager] createFileAtPath:cacheFilePath contents:nil attributes:nil];
            fileExist = fileExist && [[NSFileManager defaultManager] createFileAtPath:indexFilePath contents:nil attributes:nil];
        }
        
        if (!fileExist)
        {
            return nil;
        }
        
        _cacheFilePath = cacheFilePath;
        _indexFilePath = indexFilePath;
        self.ranges = [[NSMutableArray alloc] init];
        self.readFileHandle = [NSFileHandle fileHandleForReadingAtPath:_cacheFilePath];
        self.writeFileHandle = [NSFileHandle fileHandleForWritingAtPath:_cacheFilePath];
        _recieveMaxCount = 0;
        
        NSString *indexStr = [NSString stringWithContentsOfFile:_indexFilePath encoding:NSUTF8StringEncoding error:nil];
        NSData *data = [indexStr dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *indexDic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers | NSJSONReadingAllowFragments error:nil];
        if (![self serializeIndex:indexDic])
        {
            [self truncateFileWithFileLength:0];
        }
        [self checkCompelete];
    }
    return self;
}

+ (NSString *)indexFileExtension
{
    return @".idx!";
}

- (void)dealloc
{
    LOG_I(@"释放 SQRPlayerItemCacheFile",nil);
    
    [self.readFileHandle closeFile];
    [self.writeFileHandle closeFile];
}

#pragma mark - serialize
- (BOOL)serializeIndex:(NSDictionary *)indexDic
{
    if (![indexDic isKindOfClass:[NSDictionary class]])
    {
        return NO;
    }
    
    NSNumber *fileSize = indexDic[MCAVPlayerCacheFileSizeKey];
    if (fileSize != nil && [fileSize isKindOfClass:[NSNumber class]])
    {
        _fileLength = [fileSize unsignedIntegerValue];
    }
    
    if (_fileLength == 0)
    {
        return NO;
    }
    
    [self.ranges removeAllObjects];
    NSMutableArray *rangeArray = indexDic[MCAVPlayerCacheFileZoneKey];
    for (NSString *rangeStr in rangeArray)
    {
        NSRange range = NSRangeFromString(rangeStr);
        [self.ranges addObject:[NSValue valueWithRange:range]];
    }
    
    _responseHeaders = indexDic[MCAVPlayerCacheFileResponseHeadersKey];
    
    return YES;
}

- (NSString *)unserializeIndex
{
    NSMutableArray *rangeArray = [[NSMutableArray alloc] init];
    for (NSValue *range in self.ranges)
    {
        [rangeArray addObject:NSStringFromRange([range rangeValue])];
    }
    NSMutableDictionary *dict = [@{
                                    MCAVPlayerCacheFileSizeKey: @(_fileLength),
                                    MCAVPlayerCacheFileZoneKey: rangeArray
                                    } mutableCopy];
    if (_responseHeaders)
    {
        dict[MCAVPlayerCacheFileResponseHeadersKey] = _responseHeaders;
    }
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (data)
    {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (BOOL)synchronize
{
    @synchronized (self) {
        _recieveMaxCount = 0;
        NSString *indexStr = [self unserializeIndex];
        return [indexStr writeToFile:_indexFilePath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}

#pragma mark - property
- (NSUInteger)cachedDataBound
{
    if (self.ranges.count > 0)
    {
        NSRange range = [[self.ranges lastObject] rangeValue];
        return NSMaxRange(range);
    }
    return 0;
}

- (BOOL)isFileLengthValid
{
    return _fileLength != 0;
}

- (BOOL)isCompeleted
{
    return _compelete;
}

- (BOOL)isEof
{
    if (_readOffset + 1 >= _fileLength)
    {
        return YES;
    }
    return NO;
}

#pragma mark - range
- (void)mergeRanges
{
    for (int i = 0; i < self.ranges.count; ++i)
    {
        if ((i + 1) < self.ranges.count)
        {
            NSRange currentRange = [self.ranges[i] rangeValue];
            NSRange nextRange = [self.ranges[i + 1] rangeValue];
            if (MCRangeCanMerge(currentRange, nextRange))
            {
                [self.ranges removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(i, 2)]];
                [self.ranges insertObject:[NSValue valueWithRange:NSUnionRange(currentRange, nextRange)] atIndex:i];
                i -= 1;
            }
        }
    }
}

- (void)addRange:(NSRange)range
{
    if (range.length == 0 || range.location >= _fileLength)
    {
        return;
    }
    
    BOOL inserted = NO;
    for (int i = 0; i < self.ranges.count; ++i)
    {
        NSRange currentRange = [self.ranges[i] rangeValue];
        if (currentRange.location >= range.location)
        {
            [self.ranges insertObject:[NSValue valueWithRange:range] atIndex:i];
            inserted = YES;
            break;
        }
    }
    if (!inserted)
    {
        [self.ranges addObject:[NSValue valueWithRange:range]];
    }
    
    [self mergeRanges];
    [self checkCompelete];
}

- (NSRange)cachedRangeForRange:(NSRange)range
{
    NSRange cachedRange = [self cachedRangeContainsPosition:range.location];
    // 获取相同区域
    NSRange ret = NSIntersectionRange(cachedRange, range);
    if (ret.length > 0)
    {
        return ret;
    }
    else
    {
        return MCInvalidRange;
    }
}

- (NSRange)cachedRangeContainsPosition:(NSUInteger)pos
{
    @synchronized (self) {
        if (pos >= _fileLength)
        {
            return MCInvalidRange;
        }
        
        for (int i = 0; i < self.ranges.count; ++i)
        {
            NSRange range = [self.ranges[i] rangeValue];
            if (NSLocationInRange(pos, range))
            {
                return range;
            }
        }
        return MCInvalidRange;
    }
}

- (NSRange)firstNotCachedRangeFromPosition:(NSUInteger)pos
{
    if (pos >= _fileLength)
    {
        return MCInvalidRange;
    }
    
    NSUInteger start = pos;
    for (int i = 0; i < self.ranges.count; ++i)
    {
        NSRange range = [self.ranges[i] rangeValue];
        if (NSLocationInRange(start, range))
        {
            start = NSMaxRange(range);
        }
        else
        {
            if (start >= NSMaxRange(range))
            {
                continue;
            }
            else
            {
                return NSMakeRange(start, range.location - start);
            }
        }
    }
    
    if (start < _fileLength)
    {
        return NSMakeRange(start, _fileLength - start);
    }
    return MCInvalidRange;
}

- (void)checkCompelete
{
    if (self.ranges && self.ranges.count == 1)
    {
        NSRange range = [self.ranges[0] rangeValue];
        if (range.location == 0 && (range.length == _fileLength))
        {
            _compelete = YES;
            return;
        }
    }
    _compelete = NO;
}

#pragma mark - file
- (BOOL)truncateFileWithFileLength:(NSUInteger)fileLength;
{
    if (!self.writeFileHandle)
    {
        return NO;
    }
    
    _fileLength = fileLength;
    @try
    {
        [self.writeFileHandle truncateFileAtOffset:_fileLength * sizeof(Byte)];
        unsigned long long end = [self.writeFileHandle seekToEndOfFile];
        if (end != _fileLength)
        {
            return NO;
        }
    }
    @catch (NSException * e)
    {
        return NO;
    }
    
    return YES;
}

- (void)removeCache
{
    [[NSFileManager defaultManager] removeItemAtPath:_cacheFilePath error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:_indexFilePath error:NULL];
}

- (BOOL)setResponse:(NSHTTPURLResponse *)response
{
    BOOL success = YES;
    if (![self isFileLengthValid])
    {
        success = [self truncateFileWithFileLength:(NSUInteger)response.mc_fileLength];
    }
    _responseHeaders = [[response allHeaderFields] copy];
    success = success && [self synchronize];
    return success;
}

- (BOOL)saveData:(NSData *)data atOffset:(NSUInteger)offset synchronize:(BOOL)synchronize
{
    _recieveMaxCount++;
    
    if (!self.writeFileHandle)
    {
        return NO;
    }
    
    @try
    {
        [self.writeFileHandle seekToFileOffset:offset];
        [self.writeFileHandle mc_safeWriteData:data];
    }
    @catch (NSException * e)
    {
        LOG_E(@"[cache]%@",e);
        return NO;
    }
    
    @synchronized (self) {
        [self addRange:NSMakeRange(offset, [data length])];
        if (synchronize || _recieveMaxCount>kForceSynchronousMaxCount)
        {
            [self synchronize];
        }
    }
    
    return YES;
}

#pragma mark - read data
- (NSData *)dataWithRange:(NSRange)range
{
    if (!MCValidFileRange(range))
    {
        return nil;
    }
    
    if (_readOffset != range.location)
    {
        [self seekToPosition:range.location];
    }
    return [self readDataWithLength:range.length];
}

- (NSData *)readDataWithLength:(NSUInteger)length
{
    NSRange range = [self cachedRangeForRange:NSMakeRange(_readOffset, length)];
    if (MCValidFileRange(range))
    {
        NSData *data = [self.readFileHandle readDataOfLength:range.length];
        _readOffset += [data length];
        return data;
    }
    return nil;
}

#pragma mark - seek
- (void)seekToPosition:(NSUInteger)pos
{
    [self.readFileHandle seekToFileOffset:pos];
    _readOffset = (NSUInteger)self.readFileHandle.offsetInFile;
}

- (void)seekToEnd
{
    [self.readFileHandle seekToEndOfFile];
    _readOffset = (NSUInteger)self.readFileHandle.offsetInFile;
}
@end

