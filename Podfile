source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '9.0'

inhibit_all_warnings!

target 'LVWaveform' do
    # Comment this line if you're not using Swift and don't want to use dynamic frameworks
    use_frameworks!
    
    pod 'SCRecorder', :git => 'https://github.com/lvpengwei/SCRecorder.git', :commit => '121be9ffd585834a0111d3b36253052d1b1f2be9'

end


post_install do |installer|
    installer.pods_project.targets.each do |target|
        if target.name == 'VideoCore'
            target.build_configurations.each do |config|
                if config.name == 'Release'
                    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Owholemodule'
                else
                    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
                end
            end
        end
    end
end
