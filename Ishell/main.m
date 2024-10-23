//
// main.m
//
// Created by seregon
//
// This file contains the main entry point for the Ishell application.
// It sets up the command execution environment and handles the main application loop.

#import <Foundation/Foundation.h>
#import "myAppDelegate.h"

// Define a list of commonly used commands
NSArray *commonCommands = @[@"ls", @"cd", @"mkdir", @"touch", @"rm", @"cp", @"mv"];

// Function to execute a command
void executeCommand(NSString *command) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", command];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    
    NSFileHandle *file = pipe.fileHandleForReading;
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        NSData *data = [file readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"%@", output);
    } @catch (NSException *exception) {
        NSLog(@"Error executing command: %@", exception.reason);
    }
}

// Function for auto-completion
NSString *autoComplete(NSString *command) {
    for (NSString *commonCommand in commonCommands) {
        if ([command hasPrefix:commonCommand]) {
            return [commonCommand stringByAppendingString:@" "];
        }
    }
    return command;
}

// Function to handle command history
NSMutableArray *commandHistory(NSMutableArray *history, NSString *command) {
    [history addObject:command];
    if (history.count > 10) {
        [history removeObjectAtIndex:0];
    }
    return history;
}

// Function to generate the writing of the application name "Ishell"
void generateWriting(NSString *name, double delay) {
    for (NSUInteger i = 0; i < name.length; i++) {
        printf("%c", [name characterAtIndex:i]);
        fflush(stdout);
        [NSThread sleepForTimeInterval:delay];
    }
    printf("\n");
}

// Function to display the disclaimer
void displayDisclaimer() {
    NSLog(@"DISCLAIMER: This application is for educational purposes only. The creator of this application does not condone or support any illegal or unethical activities. The use of this application for any dangerous or malicious purposes is strictly prohibited. The creator of this application shall not be held responsible for any damages or legal issues caused by the misuse of this application.");
}

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		NSMutableArray *history = [NSMutableArray array];
		while (1) {
			generateWriting(@"Ishell: The first shell for iOS devices", 0.1);
			
			if (history.count == 0) {
				displayDisclaimer();
			}
			
			printf("$ ");
			char input[256];
			fgets(input, 256, stdin);
			
			NSString *command = [NSString stringWithUTF8String:input];
			command = [command stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
			
			NSString *autoCompleteCommand = autoComplete(command);
			history = commandHistory(history, autoCompleteCommand);
			
			executeCommand(autoCompleteCommand);
		}
	}
	return 0;
}
