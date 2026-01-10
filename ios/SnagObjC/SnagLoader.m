#import <Foundation/Foundation.h>

#if __has_include(<Snag/Snag-Swift.h>)
#import <Snag/Snag-Swift.h>
#elif __has_include("Snag-Swift.h")
#import "Snag-Swift.h"
#endif

#import <dlfcn.h>

@interface SnagLoader : NSObject
@end

@implementation SnagLoader

+ (void)hookRCTLog:(Class)snagClass {
  void (*RCTSetLogFunction)(void *) = dlsym(RTLD_DEFAULT, "RCTSetLogFunction");
  if (RCTSetLogFunction) {
    typedef void (^RCTLogFunction)(NSInteger, NSInteger, NSString *, NSNumber *,
                                   NSString *);
    RCTLogFunction logHook = ^(NSInteger level, NSInteger source,
                               NSString *fileName, NSNumber *lineNumber,
                               NSString *message) {
      NSString *levelStr = @"info";
      if (level == 2)
        levelStr = @"warn";
      else if (level >= 3)
        levelStr = @"error";

      // Call Snag.log(message, level, tag)
      SEL logSelector = NSSelectorFromString(@"log:level:tag:details:");
      if ([snagClass respondsToSelector:logSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [snagClass performSelector:logSelector
                        withObject:message
                        withObject:levelStr];
        // Note: performSelector:withObject:withObject: only supports 2 args.
        // For 4 args we could use NSInvocation, but for zero-config simplicity
        // we'll stick to basic logs or use a simpler 3-arg log if available.
#pragma clang diagnostic pop
      }

      // Call original log function if we can find it
      void (*_RCTDefaultLogFunction)(NSInteger, NSInteger, NSString *,
                                     NSNumber *, NSString *) =
          dlsym(RTLD_DEFAULT, "_RCTDefaultLogFunction");
      if (_RCTDefaultLogFunction) {
        _RCTDefaultLogFunction(level, source, fileName, lineNumber, message);
      }
    };
    RCTSetLogFunction((__bridge void *)logHook);
  }
}

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

      // Try to hook RCTLog for React Native zero-config support
      [self hookRCTLog:snagClass];
    } else {
      NSLog(@"[Snag] Failed to auto-start: 'Snag' class not found.");
    }
  }
}

@end
