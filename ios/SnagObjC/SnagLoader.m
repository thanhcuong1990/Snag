#import <Foundation/Foundation.h>

#if __has_include(<Snag/Snag-Swift.h>)
#import <Snag/Snag-Swift.h>
#elif __has_include("Snag-Swift.h")
#import "Snag-Swift.h"
#endif

@interface SnagLoader : NSObject
@end

@implementation SnagLoader

+ (void)load {
  BOOL shouldStart = NO;

#ifdef DEBUG
  shouldStart = YES;
#endif

  // Check for force-enable flag in Info.plist or Launch Argument
  if (!shouldStart) {
    // 1. Check Info.plist
    id enabled =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SnagEnabled"];
    if (enabled && [enabled respondsToSelector:@selector(boolValue)]) {
      shouldStart = [enabled boolValue];
    }

    // 2. Check Launch Arguments (e.g. -SnagEnabled passed via Xcode Scheme)
    if (!shouldStart) {
      NSArray *arguments = [[NSProcessInfo processInfo] arguments];
      if ([arguments containsObject:@"-SnagEnabled"]) {
        shouldStart = YES;
      }
    }
  }

  if (shouldStart) {
    Class snagClass = NSClassFromString(@"Snag");
    if (snagClass) {
      NSLog(@"[Snag] Auto-starting...");
      [snagClass performSelector:@selector(start)];
    } else {
      NSLog(@"[Snag] Failed to auto-start: 'Snag' class not found.");
    }
  }
}

@end
