package com.snag.reactnative

import com.facebook.react.TurboReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import java.util.HashMap

class SnagPackage : TurboReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
    return if (name == SnagModule.NAME) {
      SnagModule(reactContext)
    } else {
      null
    }
  }

  override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
    return ReactModuleInfoProvider {
      val moduleInfos: MutableMap<String, ReactModuleInfo> = HashMap()
      moduleInfos[SnagModule.NAME] = ReactModuleInfo(
        SnagModule.NAME,
        SnagModule.NAME,
        false,  // canOverrideExistingModule
        false,  // needsEagerInit
        true,   // hasConstants
        false,  // isCxxModule
        true    // isTurboModule
      )
      moduleInfos
    }
  }
}
