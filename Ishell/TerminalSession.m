#import "TerminalSession.h"
#import <Foundation/Foundation.h>

@implementation TerminalSession

- (instancetype)init {
    self = [super init];
    if (self) {
        self.currentDirectory = NSHomeDirectory();
        self.commandHistory = [NSMutableArray array];
        self.logEntries = [NSMutableArray array];
        self.environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
        self.historyIndex = -1;
    }
    return self;
}

- (NSString *)runCommand:(NSString *)command {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", command];
    task.currentDirectoryPath = self.currentDirectory;
    task.environment = self.environment;
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    
    NSFileHandle *file = pipe.fileHandleForReading;
    
    [task launch];
    [task waitUntilExit];
    
    NSData *data = [file readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return output;
}

@end
