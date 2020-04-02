#
# Be sure to run `pod lib lint Network.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Network'
  s.version          = '3.1.5'
  s.summary          = 'Using network request easily'

  s.description      = <<-DESC
    Using builder to simply the way to create new requests.
                       DESC

  s.homepage         = 'https://github.com/lovesunstar/Network'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Suen' => 'lovesunstar@sina.com' }
  s.source           = { :git => 'https://github.com/lovesunstar/Network.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/_lovesunstar'

  s.ios.deployment_target = '10.0'

  s.source_files = 'Network/Classes/**/*'

  s.frameworks = 'Foundation'
  s.dependency 'Alamofire'
end
