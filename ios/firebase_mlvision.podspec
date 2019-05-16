#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'firebase_mlvision'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'https://github.com/rishab2113/firebase_mlvision/tree/master'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Rishab Nayak' => 'rishab@bu.edu' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'FirebaseCore'
  s.dependency 'FirebaseMLCommon'
  s.dependency 'FirebaseMLVision'
  s.dependency 'FirebaseMLVisionAutoML'
  s.ios.deployment_target = '9.0'
  s.static_framework = true
end
