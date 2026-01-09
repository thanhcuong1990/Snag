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

  // Check for force-enable flag in Info.plist
  if (!shouldStart) {
    id enabled =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SnagEnabled"];
    if (enabled && [enabled respondsToSelector:@selector(boolValue)]) {
      shouldStart = [enabled boolValue];
    }
  }

  if (shouldStart && NSClassFromString(@"Snag")) {
    [NSClassFromString(@"Snag") performSelector:@selector(start)];
  }
}

@end
