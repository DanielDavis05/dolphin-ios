// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "EmulationViewController.h"

#import "Core/Config/MainSettings.h"
#import "Core/Core.h"
#import "Core/Host.h"

#import "EmulationCoordinator.h"
#import "LocalizationUtil.h"

@interface EmulationViewController ()

@end

@implementation EmulationViewController {
  bool _didStartEmulation;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  _didStartEmulation = false;
  
  [[EmulationCoordinator shared] registerMainDisplayView:self.rendererView];
  
  // Create right bar button items
  self.stopButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(stopPressed)];
  self.pauseButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPause target:self action:@selector(pausePressed)];
  self.playButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:self action:@selector(playPressed)];
  
  self.navigationItem.rightBarButtonItems = @[
    self.stopButton,
    self.pauseButton
  ];
  
  [self.navigationController setNavigationBarHidden:true animated:true];
  
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveEmulationEndNotification) name:DOLEmulationDidEndNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  
  if (!_didStartEmulation) {
    [[EmulationCoordinator shared] runEmulationWithBootParameter:self.bootParameter];
    
    _didStartEmulation = true;
  }
}

- (void)updateNavigationBar:(bool)hidden {
  [self.navigationController setNavigationBarHidden:hidden animated:true];
  
  [self setNeedsStatusBarAppearanceUpdate];
  
  // Adjust the safe area insets.
  UIEdgeInsets insets = self.additionalSafeAreaInsets;
  if (hidden) {
    insets.top = 0;
  } else {
    // The safe area should extend behind the navigation bar.
    // This makes the bar "float" on top of the content.
    insets.top = -(self.navigationController.navigationBar.bounds.size.height);
  }
  
  self.additionalSafeAreaInsets = insets;
}

- (void)stopPressed {
  void (^stop)() = ^{
    Host_Message(HostMessageID::WMUserStop);
  };
  
  if (Config::Get(Config::MAIN_CONFIRM_ON_STOP)) {
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Confirm") message:DOLCoreLocalizedString(@"Do you want to stop the current emulation?") preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"No") style:UIAlertActionStyleDefault handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"Yes") style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
      stop();
    }]];
    
    [self presentViewController:alert animated:true completion:nil];
  } else {
    stop();
  }
}

- (void)pausePressed {
  Core::SetState(Core::State::Paused);
  
  self.navigationItem.rightBarButtonItems = @[
    self.stopButton,
    self.playButton
  ];
}

- (void)playPressed {
  Core::SetState(Core::State::Running);
  
  self.navigationItem.rightBarButtonItems = @[
    self.stopButton,
    self.pauseButton
  ];
}

- (void)receiveEmulationEndNotification {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.navigationController dismissViewControllerAnimated:true completion:^{
      if (![EmulationCoordinator shared].isExternalDisplayConnected) {
        [[EmulationCoordinator shared] clearMetalLayer];
      }
    }];
  });
}

@end
