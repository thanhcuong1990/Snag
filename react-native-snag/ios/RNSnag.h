#import <Foundation/Foundation.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import "RNSnagSpec/RNSnagSpec.h"

@interface RNSnag : NSObject <NativeSnagSpec>
#else
#import <React/RCTBridgeModule.h>

@interface RNSnag : NSObject <RCTBridgeModule>
#endif

@end
