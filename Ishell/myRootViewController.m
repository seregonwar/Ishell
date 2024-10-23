#import "myRootViewController.h"
#import <signal.h>
#import <AudioToolbox/AudioToolbox.h>

@interface myRootViewController () <UITextFieldDelegate>
@property (nonatomic, strong) NSMutableArray *commandHistory;
@property (nonatomic, assign) NSInteger historyIndex;
@property (nonatomic, strong) NSString *currentDirectory;
@property (nonatomic, strong) NSMutableDictionary *environment;
@property (nonatomic, strong) NSArray *builtInCommands;
@property (nonatomic, strong) UIViewController *authorViewController;
@property (nonatomic, strong) UIViewController *settingsViewController;
@property (nonatomic, strong) UIView *consoleView;
@property (nonatomic, strong) UIVisualEffectView *blurEffectView;
@property (nonatomic, strong) NSDictionary *supportedCommands;
@property (nonatomic, assign) BOOL showChannelLinks;
@property (nonatomic, assign) NSInteger versionTapCount;
@end

@implementation myRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ishell";
    
    self.sessions = [NSMutableArray array];
    [self addNewSession];
    
    self.commandTextField = [[UITextField alloc] initWithFrame:CGRectMake(10, 80, self.view.frame.size.width - 20, 40)];
    self.commandTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.commandTextField.placeholder = @"Enter command";
    self.commandTextField.delegate = self;
    [self.view addSubview:self.commandTextField];
    
    UIButton *executeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    executeButton.frame = CGRectMake(10, 130, self.view.frame.size.width - 20, 40);
    [executeButton setTitle:@"Execute" forState:UIControlStateNormal];
    [executeButton addTarget:self action:@selector(executeCommand) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:executeButton];
    
    self.logTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 180, self.view.frame.size.width, self.view.frame.size.height - 180) style:UITableViewStylePlain];
    self.logTableView.dataSource = self;
    self.logTableView.delegate = self;
    [self.view addSubview:self.logTableView];
    
    // Aggiungi pulsante "+" per nuove sessioni
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addNewSession)];
    self.navigationItem.rightBarButtonItem = addButton;
    
    // Aggiungi pulsante per il menu delle sessioni
    UIBarButtonItem *menuButton = [[UIBarButtonItem alloc] initWithTitle:@"Sessions" style:UIBarButtonItemStylePlain target:self action:@selector(showSessionMenu)];
    self.navigationItem.leftBarButtonItem = menuButton;
    
    // Gestione dei segnali
    signal(SIGINT, SIG_IGN);
    
    [self setupTabBar];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [self applyBackgroundColor];
    
    [self setupConsoleView];
    [self setupBlurEffect];
    [self styleInputField];
    [self styleExecuteButton];
    [self customizeTabBar];
    
    [self setupSupportedCommands];
    
    self.showChannelLinks = [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowChannelLinks"];
    self.versionTapCount = 0;
}

- (void)addNewSession {
    TerminalSession *newSession = [[TerminalSession alloc] init];
    [self.sessions addObject:newSession];
    self.currentSessionIndex = self.sessions.count - 1;
    [self writeChannelLinks];
    [self.logTableView reloadData];
}

- (void)showSessionMenu {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Sessions" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSInteger i = 0; i < self.sessions.count; i++) {
        [alertController addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Session %ld", (long)i+1] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.currentSessionIndex = i;
            [self.logTableView reloadData];
        }]];
    }
    
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)executeCommand {
    NSString *commandString = self.commandTextField.text;
    if (commandString.length > 0) {
        TerminalSession *currentSession = self.sessions[self.currentSessionIndex];
        [currentSession.commandHistory addObject:commandString];
        currentSession.historyIndex = currentSession.commandHistory.count;
        [currentSession.logEntries insertObject:[NSString stringWithFormat:@"%@$ %@", currentSession.currentDirectory, commandString] atIndex:0];
        
        NSArray *commandComponents = [commandString componentsSeparatedByString:@" "];
        NSString *command = commandComponents.firstObject;
        NSArray *args = [commandComponents subarrayWithRange:NSMakeRange(1, commandComponents.count - 1)];
        
        NSString *output;
        if (self.supportedCommands[command]) {
            NSString * (^commandBlock)(NSArray *) = self.supportedCommands[command];
            output = commandBlock(args);
        } else {
            output = [self runExternalCommand:commandString];
        }
        
        [currentSession.logEntries insertObject:output atIndex:0];
        [self.logTableView reloadData];
        self.commandTextField.text = @"";
    }
}

- (NSString *)listDirectory:(NSArray *)args {
    NSString *path = args.count > 0 ? args[0] : self.currentDirectory;
    NSError *error;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (error) {
        return [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
    }
    return [contents componentsJoinedByString:@"\n"];
}

- (NSString *)changeDirectory:(NSString *)newDir {
    if (!newDir) {
        newDir = NSHomeDirectory();
    }
    NSString *fullPath = [self.currentDirectory stringByAppendingPathComponent:newDir];
    BOOL isDirectory;
    if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory] && isDirectory) {
        self.currentDirectory = fullPath;
        return @"";
    } else {
        return [NSString stringWithFormat:@"cd: %@: No such directory", newDir];
    }
}

- (NSString *)makeDirectory:(NSString *)dirName {
    NSString *fullPath = [self.currentDirectory stringByAppendingPathComponent:dirName];
    NSError *error;
    if ([[NSFileManager defaultManager] createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        return @"";
    } else {
        return [NSString stringWithFormat:@"mkdir: %@", error.localizedDescription];
    }
}

- (NSString *)removeFile:(NSString *)fileName {
    NSString *fullPath = [self.currentDirectory stringByAppendingPathComponent:fileName];
    NSError *error;
    if ([[NSFileManager defaultManager] removeItemAtPath:fullPath error:&error]) {
        return @"";
    } else {
        return [NSString stringWithFormat:@"rm: %@", error.localizedDescription];
    }
}

- (NSString *)copyFile:(NSString *)source to:(NSString *)destination {
    NSString *sourcePath = [self.currentDirectory stringByAppendingPathComponent:source];
    NSString *destPath = [self.currentDirectory stringByAppendingPathComponent:destination];
    NSError *error;
    if ([[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:destPath error:&error]) {
        return @"";
    } else {
        return [NSString stringWithFormat:@"cp: %@", error.localizedDescription];
    }
}

- (NSString *)moveFile:(NSString *)source to:(NSString *)destination {
    NSString *sourcePath = [self.currentDirectory stringByAppendingPathComponent:source];
    NSString *destPath = [self.currentDirectory stringByAppendingPathComponent:destination];
    NSError *error;
    if ([[NSFileManager defaultManager] moveItemAtPath:sourcePath toPath:destPath error:&error]) {
        return @"";
    } else {
        return [NSString stringWithFormat:@"mv: %@", error.localizedDescription];
    }
}

- (NSString *)catFile:(NSString *)fileName {
    NSString *fullPath = [self.currentDirectory stringByAppendingPathComponent:fileName];
    NSError *error;
    NSString *contents = [NSString stringWithContentsOfFile:fullPath encoding:NSUTF8StringEncoding error:&error];
    if (contents) {
        return contents;
    } else {
        return [NSString stringWithFormat:@"cat: %@", error.localizedDescription];
    }
}

- (NSString *)grepInFile:(NSString *)fileName forPattern:(NSString *)pattern {
    NSString *fullPath = [self.currentDirectory stringByAppendingPathComponent:fileName];
    NSError *error;
    NSString *contents = [NSString stringWithContentsOfFile:fullPath encoding:NSUTF8StringEncoding error:&error];
    if (!contents) {
        return [NSString stringWithFormat:@"grep: %@", error.localizedDescription];
    }
    
    NSMutableString *result = [NSMutableString string];
    [contents enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if ([line rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound) {
            [result appendFormat:@"%@\n", line];
        }
    }];
    
    return result;
}

- (NSString *)touchFile:(NSString *)fileName {
    NSString *fullPath = [self.currentDirectory stringByAppendingPathComponent:fileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        return [[NSFileManager defaultManager] createFileAtPath:fullPath contents:nil attributes:nil] ? @"" : @"touch: Unable to create file";
    }
    return @"";
}

- (void)clearConsole {
    TerminalSession *currentSession = self.sessions[self.currentSessionIndex];
    [currentSession.logEntries removeAllObjects];
    [self.logTableView reloadData];
}

- (NSString *)showHelp {
    return @"Available commands:\n"
           @"ls - List directory contents\n"
           @"cd - Change directory\n"
           @"pwd - Print working directory\n"
           @"echo - Display a line of text\n"
           @"mkdir - Make directories\n"
           @"rm - Remove files or directories\n"
           @"cp - Copy files and directories\n"
           @"mv - Move (rename) files\n"
           @"cat - Concatenate files and print on the standard output\n"
           @"grep - Print lines matching a pattern\n"
           @"touch - Change file timestamps\n"
           @"clear - Clear the terminal screen\n"
           @"help - Display this help message";
}

- (NSString *)runExternalCommand:(NSString *)command {
    // Implementazione esistente per eseguire comandi esterni
    return [self runCommand:command];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if ([string isEqualToString:@"\n"]) {
        [self executeCommand];
        return NO;
    } else if ([string isEqualToString:@"\t"]) {
        [self autoComplete];
        return NO;
    }
    return YES;
}

- (void)autoComplete {
    NSString *currentText = self.commandTextField.text;
    NSArray *allCommands = [self.builtInCommands arrayByAddingObjectsFromArray:@[@"ls", @"mkdir", @"touch", @"rm", @"cp", @"mv"]];
    
    for (NSString *cmd in allCommands) {
        if ([cmd hasPrefix:currentText]) {
            self.commandTextField.text = cmd;
            break;
        }
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self executeCommand];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.historyIndex = self.commandHistory.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sessions[self.currentSessionIndex].logEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont fontWithName:@"Courier" size:12];
    }
    cell.textLabel.text = self.sessions[self.currentSessionIndex].logEntries[indexPath.row];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [UIColor whiteColor];
    return cell;
}

// Gestione dei tasti freccia
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if ([string isEqualToString:UIKeyInputUpArrow]) {
        [self navigateHistory:-1];
        return NO;
    } else if ([string isEqualToString:UIKeyInputDownArrow]) {
        [self navigateHistory:1];
        return NO;
    }
    return YES;
}

- (void)navigateHistory:(NSInteger)direction {
    self.historyIndex += direction;
    if (self.historyIndex < 0) {
        self.historyIndex = 0;
    } else if (self.historyIndex >= self.commandHistory.count) {
        self.historyIndex = self.commandHistory.count;
        self.commandTextField.text = @"";
    } else {
        self.commandTextField.text = self.commandHistory[self.historyIndex];
    }
}

- (void)setupTabBar {
    self.tabBarController = [[UITabBarController alloc] init];
    self.tabBarController.delegate = self;
    
    UIViewController *terminalVC = [[UIViewController alloc] init];
    terminalVC.view = self.view;
    terminalVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Terminal" image:[UIImage systemImageNamed:@"terminal"] tag:0];
    
    self.authorViewController = [self createAuthorViewController];
    self.settingsViewController = [self createSettingsViewController];
    
    self.tabBarController.viewControllers = @[terminalVC, self.authorViewController, self.settingsViewController];
    
    [self.view addSubview:self.tabBarController.tabBar];
    self.tabBarController.tabBar.frame = CGRectMake(0, self.view.frame.size.height - 49, self.view.frame.size.width, 49);
}

- (UIViewController *)createAuthorViewController {
    UIViewController *authorVC = [[UIViewController alloc] init];
    authorVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Author" image:[UIImage systemImageNamed:@"person.circle"] tag:1];
    
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:authorVC.view.bounds];
    [authorVC.view addSubview:scrollView];
    
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 20;
    stackView.alignment = UIStackViewAlignmentCenter;
    [scrollView addSubview:stackView];
    
    // Avatar
    NSURL *avatarURL = [NSURL URLWithString:@"https://avatars.githubusercontent.com/u/109359355?v=4"];
    NSData *avatarData = [NSData dataWithContentsOfURL:avatarURL];
    UIImage *avatarImage = [UIImage imageWithData:avatarData];
    UIImageView *avatarView = [[UIImageView alloc] initWithImage:avatarImage];
    avatarView.frame = CGRectMake(0, 0, 100, 100);
    avatarView.layer.cornerRadius = 50;
    avatarView.clipsToBounds = YES;
    [stackView addArrangedSubview:avatarView];
    
    // Social links
    NSArray *socialLinks = @[
        @{@"title": @"GitHub", @"url": @"https://github.com/seregonwar"},
        @{@"title": @"Twitter", @"url": @"https://x.com/SeregonWar"},
        @{@"title": @"Reddit", @"url": @"https://www.reddit.com/user/S3R3GON/"}
    ];
    
    for (NSDictionary *link in socialLinks) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:link[@"title"] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(openSocialLink:) forControlEvents:UIControlEventTouchUpInside];
        button.tag = [socialLinks indexOfObject:link];
        [stackView addArrangedSubview:button];
    }
    
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:20],
        [stackView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [stackView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-20],
        [stackView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor]
    ]];
    
    return authorVC;
}

- (UIViewController *)createSettingsViewController {
    UIViewController *settingsVC = [[UIViewController alloc] init];
    settingsVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:[UIImage systemImageNamed:@"gear"] tag:2];
    
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 20;
    stackView.alignment = UIStackViewAlignmentLeading;
    [settingsVC.view addSubview:stackView];
    
    UILabel *colorLabel = [[UILabel alloc] init];
    colorLabel.text = @"Background Color:";
    [stackView addArrangedSubview:colorLabel];
    
    UISegmentedControl *colorControl = [[UISegmentedControl alloc] initWithItems:@[@"Light", @"Dark", @"System"]];
    [colorControl addTarget:self action:@selector(changeBackgroundColor:) forControlEvents:UIControlEventValueChanged];
    [stackView addArrangedSubview:colorControl];
    
    UILabel *showLinksLabel = [[UILabel alloc] init];
    showLinksLabel.text = @"Show Channel Links:";
    [stackView addArrangedSubview:showLinksLabel];
    
    UISwitch *showLinksSwitch = [[UISwitch alloc] init];
    [showLinksSwitch addTarget:self action:@selector(toggleShowChannelLinks:) forControlEvents:UIControlEventValueChanged];
    showLinksSwitch.on = self.showChannelLinks;
    [stackView addArrangedSubview:showLinksSwitch];
    
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = @"Version: 1.0";
    versionLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(versionLabelTapped)];
    [versionLabel addGestureRecognizer:tapGesture];
    [stackView addArrangedSubview:versionLabel];
    
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:settingsVC.view.safeAreaLayoutGuide.topAnchor constant:20],
        [stackView.leadingAnchor constraintEqualToAnchor:settingsVC.view.leadingAnchor constant:20],
        [stackView.trailingAnchor constraintEqualToAnchor:settingsVC.view.trailingAnchor constant:-20]
    ]];
    
    return settingsVC;
}

- (void)openSocialLink:(UIButton *)sender {
    NSArray *socialLinks = @[
        @"https://github.com/seregonwar",
        @"https://x.com/SeregonWar",
        @"https://www.reddit.com/user/S3R3GON/"
    ];
    NSURL *url = [NSURL URLWithString:socialLinks[sender.tag]];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)changeBackgroundColor:(UISegmentedControl *)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:sender.selectedSegmentIndex forKey:@"BackgroundColorPreference"];
    [defaults synchronize];

    [self applyBackgroundColor];
}

- (void)applyBackgroundColor {
    NSInteger colorPreference = [[NSUserDefaults standardUserDefaults] integerForKey:@"BackgroundColorPreference"];
    UIColor *backgroundColor;
    UIBlurEffectStyle blurStyle;
    
    switch (colorPreference) {
        case 0: // Light
            backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
            blurStyle = UIBlurEffectStyleLight;
            break;
        case 1: // Dark
            backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
            blurStyle = UIBlurEffectStyleDark;
            break;
        case 2: // System
            if (@available(iOS 13.0, *)) {
                backgroundColor = [UIColor systemBackgroundColor];
                blurStyle = UIBlurEffectStyleRegular;
            } else {
                backgroundColor = [UIColor whiteColor];
                blurStyle = UIBlurEffectStyleLight;
            }
            break;
    }
    
    self.consoleView.backgroundColor = backgroundColor;
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
    self.blurEffectView.effect = blurEffect;
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    [UIView animateWithDuration:0.3 animations:^{
        CGRect f = self.view.frame;
        f.origin.y = -keyboardSize.height;
        self.view.frame = f;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [UIView animateWithDuration:0.3 animations:^{
        CGRect f = self.view.frame;
        f.origin.y = 0.0f;
        self.view.frame = f;
    }];
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    [UIView transitionWithView:tabBarController.view
                      duration:0.3
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
                        // Animazione personalizzata qui, se necessario
                    }
                    completion:nil];
}

- (void)textField:(UITextField *)textField didChangeSelection:(UITextRange *)selectedRange {
    [self showAutoCompleteSuggestions];
}

- (void)showAutoCompleteSuggestions {
    NSString *currentText = self.commandTextField.text;
    NSArray *allCommands = [self.builtInCommands arrayByAddingObjectsFromArray:@[@"ls", @"mkdir", @"touch", @"rm", @"cp", @"mv"]];
    NSMutableArray *suggestions = [NSMutableArray array];
    
    for (NSString *cmd in allCommands) {
        if ([cmd hasPrefix:currentText]) {
            [suggestions addObject:cmd];
        }
    }
    
    // Mostra i suggerimenti in un UITableView sotto il campo di input
    // Implementa la logica per mostrare e nascondere questa tabella dei suggerimenti
}

- (void)setupConsoleView {
    self.consoleView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.consoleView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    [self.view insertSubview:self.consoleView atIndex:0];
}

- (void)setupBlurEffect {
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurEffectView.frame = self.view.bounds;
    self.blurEffectView.alpha = 0.7;
    [self.consoleView addSubview:self.blurEffectView];
}

- (void)styleInputField {
    self.commandTextField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.commandTextField.textColor = [UIColor whiteColor];
    self.commandTextField.font = [UIFont fontWithName:@"Menlo" size:14];
    self.commandTextField.layer.cornerRadius = 8;
    self.commandTextField.layer.borderWidth = 1;
    self.commandTextField.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:1.0].CGColor;
}

- (void)styleExecuteButton {
    UIButton *executeButton = [self.view viewWithTag:100]; // Assumi che abbiamo assegnato un tag al pulsante
    executeButton.backgroundColor = [UIColor systemBlueColor];
    executeButton.layer.cornerRadius = 8;
    [executeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    executeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
}

- (void)customizeTabBar {
    self.tabBarController.tabBar.tintColor = [UIColor systemBlueColor];
    self.tabBarController.tabBar.unselectedItemTintColor = [UIColor lightGrayColor];
    self.tabBarController.tabBar.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
}

- (void)changeToSession:(NSInteger)sessionIndex {
    [UIView transitionWithView:self.logTableView
                      duration:0.3
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
                        self.currentSessionIndex = sessionIndex;
                        [self.logTableView reloadData];
                    }
                    completion:nil];
}

- (void)setupSupportedCommands {
    self.supportedCommands = @{
        @"ls": ^(NSArray *args) { return [self listDirectory:args]; },
        @"cd": ^(NSArray *args) { return [self changeDirectory:args.firstObject]; },
        @"pwd": ^(NSArray *args) { return self.currentDirectory; },
        @"echo": ^(NSArray *args) { return [args componentsJoinedByString:@" "]; },
        @"mkdir": ^(NSArray *args) { return [self makeDirectory:args.firstObject]; },
        @"rm": ^(NSArray *args) { return [self removeFile:args.firstObject]; },
        @"cp": ^(NSArray *args) { return [self copyFile:args[0] to:args[1]]; },
        @"mv": ^(NSArray *args) { return [self moveFile:args[0] to:args[1]]; },
        @"cat": ^(NSArray *args) { return [self catFile:args.firstObject]; },
        @"grep": ^(NSArray *args) { return [self grepInFile:args[1] forPattern:args[0]]; },
        @"touch": ^(NSArray *args) { return [self touchFile:args.firstObject]; },
        @"clear": ^(NSArray *args) { [self clearConsole]; return @""; },
        @"help": ^(NSArray *args) { return [self showHelp]; }
    };
}

- (void)writeChannelLinks {
    if (!self.showChannelLinks) {
        return;
    }
    
    NSArray *links = @[
        @"GitHub: https://github.com/seregonwar",
        @"Twitter: https://x.com/SeregonWar",
        @"Reddit: https://www.reddit.com/user/S3R3GON/"
    ];
    
    TerminalSession *currentSession = self.sessions[self.currentSessionIndex];
    
    for (NSString *link in links) {
        [currentSession.logEntries insertObject:link atIndex:0];
        [NSThread sleepForTimeInterval:0.5]; // Aggiungi un ritardo tra ogni riga
        [self.logTableView reloadData];
    }
}

- (void)toggleShowChannelLinks:(UISwitch *)sender {
    self.showChannelLinks = sender.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:self.showChannelLinks forKey:@"ShowChannelLinks"];
}

- (void)versionLabelTapped {
    self.versionTapCount++;
    if (self.versionTapCount == 5) {
        [self triggerEasterEgg];
        self.versionTapCount = 0;
    }
}

- (void)triggerEasterEgg {
    // Crea una vista temporanea per l'animazione
    UIView *easterEggView = [[UIView alloc] initWithFrame:self.view.bounds];
    easterEggView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:easterEggView];
    
    // Crea un'etichetta per il testo ASCII art
    UILabel *asciiLabel = [[UILabel alloc] initWithFrame:easterEggView.bounds];
    asciiLabel.numberOfLines = 0;
    asciiLabel.textAlignment = NSTextAlignmentCenter;
    asciiLabel.textColor = [UIColor greenColor];
    asciiLabel.font = [UIFont fontWithName:@"Courier" size:8];
    [easterEggView addSubview:asciiLabel];
    
    // ASCII art di un computer "hacked"
    NSString *asciiArt = @"    _________________________________________________\n"
                         @"   /                                                 \\\n"
                         @"  |    _________________________________________     |\n"
                         @"  |   |                                         |    |\n"
                         @"  |   |  C:\\> HACK THE PLANET                   |    |\n"
                         @"  |   |                                         |    |\n"
                         @"  |   |  SYSTEM COMPROMISED                     |    |\n"
                         @"  |   |  ACCESSING MAINFRAME...                 |    |\n"
                         @"  |   |  DOWNLOADING SECRET FILES...            |    |\n"
                         @"  |   |                                         |    |\n"
                         @"  |   |  CONGRATULATIONS! YOU FOUND THE         |    |\n"
                         @"  |   |  SUPER SECRET EASTER EGG!               |    |\n"
                         @"  |   |                                         |    |\n"
                         @"  |   |  NOW GO FORTH AND CODE, YOUNG PADAWAN   |    |\n"
                         @"  |   |_________________________________________|    |\n"
                         @"  |                                                  |\n"
                         @"   \\_________________________________________________/\n"
                         @"          \\___________________________________/\n"
                         @"       ___________________________________________\n"
                         @"    _-'    .-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.  --- `-_\n"
                         @" _-'.-.-. .---.-.-.-.-.-.-.-.-.-.-.-.-.-.-.--.  .-.-.`-_\n"
                         @":-------------------------------------------------------------------------:\n"
                         @"`---._.-------------------------------------------------------------._.---'";
    
    // Animazione per rivelare l'ASCII art carattere per carattere
    __block NSInteger characterIndex = 0;
    [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer * _Nonnull timer) {
        if (characterIndex < asciiArt.length) {
            asciiLabel.text = [asciiArt substringToIndex:characterIndex];
            characterIndex++;
        } else {
            [timer invalidate];
            [self performSelector:@selector(dismissEasterEgg:) withObject:easterEggView afterDelay:5.0];
        }
    }];
    
    // Riproduce un suono di "hacking"
    SystemSoundID soundID;
    NSURL *soundURL = [[NSBundle mainBundle] URLForResource:@"hacking_sound" withExtension:@"wav"];
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)soundURL, &soundID);
    AudioServicesPlaySystemSound(soundID);
}

- (void)dismissEasterEgg:(UIView *)easterEggView {
    [UIView animateWithDuration:0.5 animations:^{
        easterEggView.alpha = 0;
    } completion:^(BOOL finished) {
        [easterEggView removeFromSuperview];
    }];
}

@end
