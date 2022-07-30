// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "EmulationiOSViewController.h"

#import "Core/ConfigManager.h"
#import "Core/Config/MainSettings.h"
#import "Core/Config/WiimoteSettings.h"
#import "Core/HW/GCPad.h"
#import "Core/HW/SI/SI_Device.h"
#import "Core/HW/Wiimote.h"
#import "Core/HW/WiimoteEmu/WiimoteEmu.h"
#import "Core/State.h"

#import "InputCommon/InputConfig.h"

#import "VideoCommon/RenderBase.h"

#import "EmulationCoordinator.h"
#import "HostNotifications.h"
#import "LocalizationUtil.h"
#import "VirtualMFiControllerManager.h"

typedef NS_ENUM(NSInteger, DOLEmulationVisibleTouchPad) {
  DOLEmulationVisibleTouchPadNone,
  DOLEmulationVisibleTouchPadGameCube,
  DOLEmulationVisibleTouchPadWiimote,
  DOLEmulationVisibleTouchPadSidewaysWiimote,
  DOLEmulationVisibleTouchPadClassic
};

@interface EmulationiOSViewController ()

@end

@implementation EmulationiOSViewController {
  DOLEmulationVisibleTouchPad _visibleTouchPad;
  int _stateSlot;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  for (int i = 0; i < [self.touchPads count]; i++) {
    TCView* padView = self.touchPads[i];
    
    if (i + 1 == DOLEmulationVisibleTouchPadGameCube) {
      padView.port = 0;
    } else {
      // Wii pads are mapped to touchscreen device 4
      padView.port = 4;
    }
  }
  
  if (@available(iOS 15.0, *)) {
    // Stupidity - iOS 15 now uses the scrollEdgeAppearance when the UINavigationBar is off screen.
    // https://developer.apple.com/forums/thread/682420
    UINavigationBar* bar = self.navigationController.navigationBar;
    bar.scrollEdgeAppearance = bar.standardAppearance;
    
    VirtualMFiControllerManager* virtualMfi = [VirtualMFiControllerManager shared];
    if (virtualMfi.shouldConnectController) {
      [virtualMfi connectControllerToView:self.view];
    }
  }
  
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveTitleChangedNotification) name:DOLHostTitleChangedNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveEmulationEndNotificationiOS) name:DOLEmulationDidEndNotification object:nil];
}

- (void)recreateMenu API_AVAILABLE(ios(14.0)) {
  NSMutableArray<UIAction*>* controllerActions = [[NSMutableArray alloc] init];
  
  if (_visibleTouchPad != DOLEmulationVisibleTouchPadWiimote && SConfig::GetInstance().bWii) {
    [controllerActions addObject:[UIAction actionWithTitle:DOLCoreLocalizedString(@"Wii Remote") image:[UIImage systemImageNamed:@"gamecontroller"] identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadToWii];
      [self recreateMenu];
      
      [self.navigationController setNavigationBarHidden:true animated:true];
    }]];
  }
  
  if (_visibleTouchPad != DOLEmulationVisibleTouchPadGameCube) {
    [controllerActions addObject:[UIAction actionWithTitle:DOLCoreLocalizedString(@"GameCube Controller") image:[UIImage systemImageNamed:@"gamecontroller"] identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadToGameCube];
      [self recreateMenu];
      
      [self.navigationController setNavigationBarHidden:true animated:true];
    }]];
  }
  
  if (_visibleTouchPad != DOLEmulationVisibleTouchPadNone) {
    [controllerActions addObject:[UIAction actionWithTitle:DOLCoreLocalizedString(@"Hide") image:[UIImage systemImageNamed:@"x.circle"] identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadWithType:DOLEmulationVisibleTouchPadNone];
      [self recreateMenu];
      
      [self.navigationController setNavigationBarHidden:true animated:true];
    }]];
  }
  
  self.navigationItem.leftBarButtonItem.menu = [UIMenu menuWithChildren:@[
    [UIMenu menuWithTitle:DOLCoreLocalizedString(@"Controllers") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:controllerActions],
    [UIMenu menuWithTitle:DOLCoreLocalizedString(@"Save State") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
      [UIAction actionWithTitle:DOLCoreLocalizedString(@"Load State") image:[UIImage systemImageNamed:@"tray.and.arrow.down"] identifier:nil handler:^(UIAction*) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          State::Load(self->_stateSlot);
        });
      
        [self.navigationController setNavigationBarHidden:true animated:true];
      }],
      [UIAction actionWithTitle:DOLCoreLocalizedString(@"Save State") image:[UIImage systemImageNamed:@"tray.and.arrow.up"] identifier:nil handler:^(UIAction*) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          State::Save(self->_stateSlot);
        });
      
        [self.navigationController setNavigationBarHidden:true animated:true];
      }]
    ]]
  ]];
}

- (void)viewDidLayoutSubviews {
  if (g_renderer) {
    g_renderer->ResizeSurface();
  }
}

- (void)receiveTitleChangedNotification {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (SConfig::GetInstance().bWii) {
      [self updateVisibleTouchPadToWii];
    } else {
      [self updateVisibleTouchPadToGameCube];
    }
    
    if (@available(iOS 14.0, *)) {
      [self recreateMenu];
    }
  });
}

- (bool)isWiimoteTouchPadAttached {
  if (Config::Get(Config::GetInfoForWiimoteSource(0)) != WiimoteSource::Emulated) {
    // Nothing is plugged in to this port.
    return false;
  }
  
  const auto wiimote = static_cast<WiimoteEmu::Wiimote*>(Wiimote::GetConfig()->GetController(0));
  
  if (wiimote->GetDefaultDevice().source != "iOS") {
    // A real controller is mapped to this port.
    return false;
  }
  
  return true;
}

- (bool)isGameCubeTouchPadAttached {
  if (Config::Get(Config::GetInfoForSIDevice(0)) == SerialInterface::SIDEVICE_NONE) {
    // Nothing is plugged in to this port.
    return false;
  }
  
  const auto device = Pad::GetConfig()->GetController(0);
  
  if (device->GetDefaultDevice().source != "iOS") {
    // A real controller is mapped to this port.
    return false;
  }
  
  return true;
}

- (void)updateVisibleTouchPadToWii {
  if (![self isWiimoteTouchPadAttached]) {
    // Fallback to GameCube in case port 1 is bound to the touchscreen.
    [self updateVisibleTouchPadToGameCube];
    
    return;
  }
  
  DOLEmulationVisibleTouchPad targetTouchPad;
  
  const auto wiimote = static_cast<WiimoteEmu::Wiimote*>(Wiimote::GetConfig()->GetController(0));
  
  if (wiimote->GetActiveExtensionNumber() == WiimoteEmu::ExtensionNumber::CLASSIC) {
    targetTouchPad = DOLEmulationVisibleTouchPadClassic;
  } else if (wiimote->IsSideways()) {
    targetTouchPad = DOLEmulationVisibleTouchPadSidewaysWiimote;
  } else {
    targetTouchPad = DOLEmulationVisibleTouchPadWiimote;
  }
  
  [self updateVisibleTouchPadWithType:targetTouchPad];
}

- (void)updateVisibleTouchPadToGameCube {
  if (![self isGameCubeTouchPadAttached]) {
    return;
  }
  
  [self updateVisibleTouchPadWithType:DOLEmulationVisibleTouchPadGameCube];
}

- (void)updateVisibleTouchPadWithType:(DOLEmulationVisibleTouchPad)touchPad {
  if (_visibleTouchPad == touchPad) {
    return;
  }
  
  NSInteger targetIdx = touchPad - 1;
  
  for (int i = 0; i < [self.touchPads count]; i++) {
    TCView* padView = self.touchPads[i];
    padView.userInteractionEnabled = i == targetIdx;
  }
  
  [UIView animateWithDuration:0.5f animations:^{
    for (int i = 0; i < [self.touchPads count]; i++) {
      TCView* padView = self.touchPads[i];
      padView.alpha = i == targetIdx ? 1.0f : 0.0f;
    }
  }];
  
  _visibleTouchPad = touchPad;
}

- (IBAction)pullDownPressed:(id)sender {
  [self updateNavigationBar:false];
  
  // Automatic hide after 5 seconds
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self updateNavigationBar:true];
  });
}

- (void)receiveEmulationEndNotificationiOS {
  if (@available(iOS 15.0, *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [[VirtualMFiControllerManager shared] disconnectController];
    });
  }
}

@end
