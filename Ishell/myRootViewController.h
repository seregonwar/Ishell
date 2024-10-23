//
// myRootViewController.h
//
// Created by seregon
//
// This file defines the interface for the main view controller of the Ishell application.
// It handles the terminal interface, command execution, and tab bar functionality.

#import <UIKit/UIKit.h>
#import "TerminalSession.h"

@interface myRootViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UITabBarControllerDelegate>

@property (nonatomic, strong) UITableView *logTableView;
@property (nonatomic, strong) UITextField *commandTextField;
@property (nonatomic, strong) NSMutableArray<TerminalSession *> *sessions;
@property (nonatomic, assign) NSInteger currentSessionIndex;
@property (nonatomic, strong) UITabBarController *tabBarController;

- (void)addNewSession;
- (void)showSessionMenu;

@end
