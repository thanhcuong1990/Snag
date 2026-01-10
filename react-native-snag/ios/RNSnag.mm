#import "RNSnag.h"

#if __has_include("react_native_snag-Swift.h")
#import "react_native_snag-Swift.h"
#else
#import <react_native_snag/react_native_snag-Swift.h>
#endif

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
