
Pod::Spec.new do |s|
  s.name             = 'Snag'
  s.version          = '1.0.14'
  s.summary          = "Native cross-platform network debugger for iOS & Android - no proxies needed."

  s.description      = <<-DESC
                        A lightweight, native network debugging library for iOS and Android apps.
                        No proxy setup or certificate installation required. Integrate the library into your app and view real-time HTTP/HTTPS requests on a desktop viewer over the local network using automatic device discovery.
                        Part of a cross-platform debugging solution supporting both iOS (via Bonjour) and Android.
                       DESC

  s.homepage         = 'https://github.com/thanhcuong1990/Snag'
  s.license          = { :type => 'APACHE', :file => 'LICENSE' }
  s.author           = { 'Cuong Lam' => 'thanhcuong1990@gmail.com' }
  s.source           = { :git => 'https://github.com/thanhcuong1990/Snag.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '15.0'
  
  # Updated source files to Swift and ObjC
  s.source_files = 'ios/Snag/**/*', 'ios/SnagObjC/**/*'

  s.swift_version = '5.0'
  s.requires_arc = true

end
