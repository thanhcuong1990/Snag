package com.snag.reactnative

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.annotations.ReactModule
import com.facebook.fbreact.specs.NativeSnagSpec
import com.snag.Snag

@ReactModule(name = SnagModule.NAME)
class SnagModule(reactContext: ReactApplicationContext) : NativeSnagSpec(reactContext) {

  override fun getName(): String {
    return NAME
  }

  override fun log(message: String, level: String, tag: String) {
    Snag.log(message, level = level, tag = tag)
  }

  override fun isEnabled(): Boolean {
    return Snag.isEnabled()
  }

  companion object {
    const val NAME = "Snag"
  }
}
