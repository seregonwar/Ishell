#import <Foundation/Foundation.h>

@interface TerminalSession : NSObject

@property (nonatomic, strong) NSString *currentDirectory;
@property (nonatomic, strong) NSMutableArray *commandHistory;
@property (nonatomic, strong) NSMutableArray *logEntries;
@property (nonatomic, strong) NSMutableDictionary *environment;
@property (nonatomic, assign) NSInteger historyIndex;

- (instancetype)init;
- (NSString *)runCommand:(NSString *)command;

@end
