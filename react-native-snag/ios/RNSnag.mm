#import "RNSnag.h"

#if __has_include("react_native_snag-Swift.h")
#import "react_native_snag-Swift.h"
#else
#import <react_native_snag/react_native_snag-Swift.h>
#endif

@implementation RNSnag (AutoStart)

+ (void)load {
  BOOL shouldStart = NO;
#ifdef DEBUG
  shouldStart = YES;
#endif

  if (!shouldStart) {
    // 1. Check Info.plist
    id enabled =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SnagEnabled"];
    if (enabled && [enabled respondsToSelector:@selector(boolValue)]) {
      shouldStart = [enabled boolValue];
    }
    // 2. Check Launch Arguments
    if (!shouldStart) {
      if ([[[NSProcessInfo processInfo] arguments]
              containsObject:@"-SnagEnabled"]) {
        shouldStart = YES;
      }
    }
  }

  if (shouldStart) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          [RNSnagBridge start];
        });
  }
}

@end

@implementation RNSnag
RCT_EXPORT_MODULE(Snag)

- (void)log:(NSString *)message level:(NSString *)level tag:(NSString *)tag {
  [RNSnagBridge log:message level:level tag:tag];
}

- (BOOL)isEnabled {
  return [RNSnagBridge isEnabled];
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeSnagSpecJSI>(params);
}
#endif

@end
