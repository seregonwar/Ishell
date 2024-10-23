//
// myAppDelegate.m
//
// Created by seregon
//
// This file implements the application delegate for the Ishell application.
// It sets up the initial view controller and window.

#import "myAppDelegate.h"
#import "myRootViewController.h"

@implementation myAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	myRootViewController *rootVC = [[myRootViewController alloc] init];
	UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:rootVC];
	self.window.rootViewController = navController;
	[self.window makeKeyAndVisible];
	return YES;
}

@end
