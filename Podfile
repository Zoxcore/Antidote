source 'https://github.com/CocoaPods/Specs.git'

platform :ios, '11.0'

# ignore all warnings from all pods
inhibit_all_warnings!

def common_pods
    pod 'objcTox', :path => 'local_pod_repo/objcTox/'
    pod "cmp", :path => 'local_pod_repo/cmp'
    pod "toxcore", :path => 'local_pod_repo/toxcore'
    pod 'UITextView+Placeholder', '~> 1.1.0'
    pod 'SDCAlertView', '~> 2.5.4'
    pod 'LNNotificationsUI', :git => 'https://github.com/LeoNatan/LNNotificationsUI.git', :commit => '3f75043fc6e77b4180b76cb6cfff4faa506ab9fc'
    pod 'JGProgressHUD', '~> 1.4.0'
    pod 'SnapKit', '~> 5.6.0'
    pod 'Yaml', '~> 3.4.4'
    pod 'Firebase/Messaging', '~> 8.15.0'
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
