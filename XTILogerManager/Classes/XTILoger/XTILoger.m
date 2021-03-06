
//
//  XTILoger.m
//  XTILogerManager
//
//  Created by Input on 2018/6/17.
//  Copyright © 2018年 input. All rights reserved.
//

#import "XTILoger.h"

@interface XTILoger ()
@property (nonatomic, strong) NSFileManager *fileMgr;
@property (nonatomic, strong) dispatch_queue_t logQueue;  // 打印日志的线程队列
@property (nonatomic, strong) dispatch_queue_t saveQueue; // 保存日志的线程队列
@property (nonatomic, assign) XTILogerLevel printLevel;
@property (nonatomic, assign) XTILogerLevel saveLevel;

/// 单个日志文件大小，默认1024KB，KB为最小单位
@property (nonatomic, assign) NSInteger fileMaxSize;
/// 同一日志等级最大文件数量，默认5
@property (nonatomic, assign) NSInteger fileMaxCount;

@end

@implementation XTILoger

+ (instancetype)shared {
    static XTILoger *defaultManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultManager = [[XTILoger alloc] init];
        defaultManager.userCurrentQueue = YES;
        defaultManager.fileMaxCount = 5;
        defaultManager.fileMaxSize = 1024;
    });
    return defaultManager;
}

#pragma mark - 打印日志
- (void)logDebugWithFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *logContent = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self outLogerWith:XTILogerLevelDebug content:logContent];
}

- (void)logInfoWithFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *logContent = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self outLogerWith:XTILogerLevelInfo content:logContent];
}

- (void)logWarningWithFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *logContent = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self outLogerWith:XTILogerLevelWarning content:logContent];
}

- (void)logErrorWithFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *logContent = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self outLogerWith:XTILogerLevelError content:logContent];
}

- (void)logCrashWithFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *logContent = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self outLogerWith:XTILogerLevelCrash content:logContent];
}

- (void)log:(XTILogerLevel)level format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *logContent = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self outLogerWith:level content:logContent];
}
- (void)outLogerWith:(XTILogerLevel)level content:(NSString *)content {
#if DEBUG
    if (level >= self.printLevel) {
        if (self.userCurrentQueue) {
            NSLog(@"[%@] %@", [self getXTILogerLevelNameWith:level], content);
        } else {
            dispatch_async(self.logQueue, ^{
                NSLog(@"[%@] %@", [self getXTILogerLevelNameWith:level], content);
            });
        }
    }
#endif
    if (level < self.saveLevel) {
        return;
    }
    //构造需要写入文件的日志内容
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *formatInfo = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:now], content];
    //写文件操作
    dispatch_async(self.saveQueue, ^{
        NSString *logFileName = [self getLogerFilePathWith:level];
        // 如果文件不存在，创建文件
        if (![self.fileMgr fileExistsAtPath:logFileName]) {
            [self.fileMgr createFileAtPath:logFileName contents:nil attributes:nil];
        }
        // 获取文件大小
        NSDictionary *fileAttributes = [self.fileMgr attributesOfItemAtPath:logFileName error:nil];
        unsigned long long fileSize = [fileAttributes fileSize];

        if (fileSize >= self.fileMaxSize * 1024) {
            for (NSInteger i = self.fileMaxCount; i > 0; i--) {
                NSString *fileName = [NSString stringWithFormat:@"%@.%zd", logFileName, i];
                if (i == 0) {
                    // 文件更名
                    [self.fileMgr moveItemAtPath:logFileName toPath:[NSString stringWithFormat:@"%@.1", logFileName] error:nil];
                } else if (i == self.fileMaxCount) {
                    if ([self.fileMgr fileExistsAtPath:fileName]) {
                        [self.fileMgr removeItemAtPath:fileName error:nil];
                    }
                } else {
                    if ([self.fileMgr fileExistsAtPath:fileName]) {
                        NSString *newFileName = [NSString stringWithFormat:@"%@.%zd", logFileName, i + 1];
                        [self.fileMgr moveItemAtPath:fileName toPath:newFileName error:nil];
                    }
                }
            }

            // 重新创建新文件
            [self.fileMgr createFileAtPath:logFileName contents:nil attributes:nil];
        }

        NSFileHandle *fileHdr = [NSFileHandle fileHandleForWritingAtPath:logFileName];
        [fileHdr seekToEndOfFile];
        [fileHdr writeData:[formatInfo dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHdr closeFile];
    });
}

- (dispatch_queue_t)saveQueue {
    if (!_saveQueue) {
        _saveQueue = dispatch_queue_create("com.XTILoger.save.queue", DISPATCH_QUEUE_SERIAL);
    }
    return _saveQueue;
}

- (dispatch_queue_t)logQueue {
    if (!_logQueue) {
        _logQueue = dispatch_queue_create("com.XTILoger.log.queue", DISPATCH_QUEUE_SERIAL);
    }
    return _logQueue;
}

#pragma mark - 打印日志的等级
- (XTILogerLevel)printLevel {
    if (!_printLevel) {
        _printLevel = XTILogerLevelDebug;
    }
    return _printLevel;
}

- (XTILogerLevel)saveLevel {
    if (_saveLevel < XTILogerLevelAll) {
        _saveLevel = XTILogerLevelError;
    }
    return _saveLevel;
}

#pragma mark - 文件路径相关
- (BOOL)removeLogerFileWith:(XTILogerLevel)level {
    NSArray<NSString *> *logFileNames = [self getLogerFilePathsWith:level];
    [logFileNames enumerateObjectsUsingBlock:^(NSString *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        [self.fileMgr removeItemAtPath:[NSString stringWithFormat:@"%@/%@", self.logFolderPath, obj] error:nil];
    }];
    return YES;
}

- (NSString *)getFileLengthWithName:(NSString *)name {
    return [self getFileLengthWith:[self getXTILogerLevelWith:name]];
}

- (NSString *)getFileLengthWith:(XTILogerLevel)level {
    NSArray<NSString *> *logFileNames = [self getLogerFilePathsWith:level];
    __block unsigned long long fileSize = 0;

    [logFileNames enumerateObjectsUsingBlock:^(NSString *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        if (![obj hasPrefix:@"."]) {
            NSDictionary *fileAttributes = [self.fileMgr attributesOfItemAtPath:[NSString stringWithFormat:@"%@/%@", self.logFolderPath, obj] error:nil];
            fileSize += [fileAttributes fileSize];
        }
    }];
    NSString *lengthStr = @"B";
    float tempFileSize = fileSize;
    while (tempFileSize > 1024) {
        tempFileSize = tempFileSize / 1024;
        if ([lengthStr isEqualToString:@"B"]) {
            lengthStr = @"KB";
        } else if ([lengthStr isEqualToString:@"KB"]) {
            lengthStr = @"MB";
        }
    }
    return [NSString stringWithFormat:@"%.2f%@", tempFileSize, lengthStr];
}

- (NSArray<NSString *> *)getLogerFilePathsWith:(XTILogerLevel)level {
    NSPredicate *predicate =  [NSPredicate predicateWithFormat:@"SELF LIKE 'log_*'"];

    NSArray<NSString *> *filePaths = [[self.fileMgr contentsOfDirectoryAtPath:self.logFolderPath error:nil] filteredArrayUsingPredicate:predicate];

    if (level != XTILogerLevelAll) {
        predicate = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"SELF LIKE '%@*'", [self getXTILogerLevelNameWith:level]]];
        filePaths = [filePaths filteredArrayUsingPredicate:predicate];
    }
    return filePaths;
}

- (NSString *)getLogerFilePathWith:(XTILogerLevel)level {
    NSString *filePath = [NSString stringWithFormat:@"%@/%@.log", self.logFolderPath, [self getXTILogerLevelNameWith:level]];
    return filePath;
}

- (NSString *)getSaveLevel {
    return [self getXTILogerLevelNameWith:self.saveLevel];
}

- (NSString *)logFolderPath {
    static NSString *_logFolderPath;
    if (!_logFolderPath) {
        NSArray *cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cachePath = [cachePaths objectAtIndex:0];
        _logFolderPath = [NSString stringWithFormat:@"%@/%@", cachePath, self.class];
        BOOL isDir = NO;
        BOOL existed = [self.fileMgr fileExistsAtPath:_logFolderPath isDirectory:&isDir];
        if (!((isDir && existed))) {
            [self.fileMgr createDirectoryAtPath:_logFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    return _logFolderPath;
}

- (NSFileManager *)fileMgr {
    if (!_fileMgr) {
        _fileMgr = [NSFileManager defaultManager];
    }
    return _fileMgr;
}

- (NSString *)getXTILogerLevelNameWith:(XTILogerLevel)level {
    NSString *levelName;
    switch (level) {
        case XTILogerLevelOff:
            levelName = @"log_off";
            break;
        case XTILogerLevelInfo:
            levelName = @"log_info";
            break;
        case XTILogerLevelDebug:
            levelName = @"log_debug";
            break;
        case XTILogerLevelWarning:
            levelName = @"log_warning";
            break;
        case XTILogerLevelError:
            levelName = @"log_error";
            break;
        case XTILogerLevelCrash:
            levelName = @"log_crash";
            break;
        default:
            levelName = @"";
            break;
    }
    return levelName;
}

- (XTILogerLevel)getXTILogerLevelWith:(NSString *)name {
    XTILogerLevel level = XTILogerLevelOff;
    if ([name isEqualToString:@"log_off"]) {
        level = XTILogerLevelOff;
    } else if ([name isEqualToString:@"log_info"]) {
        level = XTILogerLevelInfo;
    } else if ([name isEqualToString:@"log_debug"]) {
        level = XTILogerLevelDebug;
    } else if ([name isEqualToString:@"log_warning"]) {
        level = XTILogerLevelWarning;
    } else if ([name isEqualToString:@"log_error"]) {
        level = XTILogerLevelError;
    } else if ([name isEqualToString:@"log_crash"]) {
        level = XTILogerLevelCrash;
    } else {
        level = XTILogerLevelAll;
    }
    return level;
}

@end
