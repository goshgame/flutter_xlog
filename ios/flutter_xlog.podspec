Pod::Spec.new do |s|
  s.name             = 'flutter_xlog'
  s.version          = '0.0.2'
  s.summary          = 'Flutter FFI bridge for Tencent mars xlog.'
  s.description      = <<-DESC
Flutter FFI plugin that exposes Tencent mars xlog APIs on iOS.
                       DESC
  s.homepage         = 'https://example.com/flutter_xlog'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'gosh' => 'dev@example.com' }
  s.source           = { :path => '.' }
  # 仅对外暴露稳定的 C 头；桥接实现随动态 xcframework 一并分发，宿主不再编译 ObjC++ 源码。
  s.source_files     = ['Classes/xlog_bridge.h']
  s.public_header_files = 'Classes/xlog_bridge.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  # 统一分发动态 flutter_xlog.xcframework，宿主仅需补齐系统 zlib 链接声明。
  s.libraries        = 'z'

  local_dynamic_xcframework = File.join(__dir__, 'Frameworks', 'flutter_xlog.xcframework')

  unless File.exist?(local_dynamic_xcframework)
    raise 'Missing Frameworks/flutter_xlog.xcframework. Run package/flutter_xlog/build_tools/build_mars_xlog.sh --ios first.'
  end

  s.vendored_frameworks = 'Frameworks/flutter_xlog.xcframework'
  s.preserve_paths = 'Frameworks/*.xcframework'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  s.swift_version = '5.0'
end
