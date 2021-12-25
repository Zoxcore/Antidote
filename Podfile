source 'https://github.com/CocoaPods/Specs.git'

platform :ios, '8.0'

# ignore all warnings from all pods
inhibit_all_warnings!

def common_pods
    pod 'objcTox', :git => 'https://github.com/Zoxcore/objcTox.git', :commit => 'b2d212eeceec3cb3920d0e42b1e48062ebf96925'
    pod 'UITextView+Placeholder', '~> 1.1.0'
    pod 'SDCAlertView', '~> 2.5.4'
    pod 'LNNotificationsUI', :git => 'https://github.com/LeoNatan/LNNotificationsUI.git', :commit => '3f75043fc6e77b4180b76cb6cfff4faa506ab9fc'
    pod 'JGProgressHUD', '~> 1.4.0'
    pod "toxcore", :git => 'https://github.com/Zoxcore/toxcore.git', :commit => 'd532bc6ea2ba417fdade32d950243a3091d3dd83'
    pod 'SnapKit'
    pod 'Yaml'
    pod 'Firebase/Messaging'
end

target :Antidote do
    common_pods
end

target :AntidoteTests do
    common_pods
    pod 'FBSnapshotTestCase/Core'
end

target :ScreenshotsUITests do
    common_pods
end
