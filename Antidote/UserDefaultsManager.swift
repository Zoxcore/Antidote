// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

class UserDefaultsManager {
    var lastActiveProfile: String? {
        get {
            return stringForKey(Keys.LastActiveProfile)
        }
        set {
            setObject(newValue as AnyObject?, forKey: Keys.LastActiveProfile)
        }
    }

    var UDPEnabled: Bool {
        get {
            return boolForKey(Keys.UDPEnabled, defaultValue: false)
        }
        set {
            setBool(newValue, forKey: Keys.UDPEnabled)
        }
    }

    var EchobotAdded: Bool {
        get {
            return boolForKey(Keys.EchobotAdded, defaultValue: false)
        }
        set {
            setBool(newValue, forKey: Keys.EchobotAdded)
        }
    }

    var DebugMode: Bool {
        get {
            return boolForKey(Keys.DebugMode, defaultValue: false)
        }
        set {
            setBool(newValue, forKey: Keys.DebugMode)
        }
    }

    var DateonmessageMode: Bool {
        get {
            return boolForKey(Keys.DateonmessageMode, defaultValue: true)
        }
        set {
            setBool(newValue, forKey: Keys.DateonmessageMode)
        }
    }

    var LongerbgMode: Bool {
        get {
            return boolForKey(Keys.LongerbgMode, defaultValue: false)
        }
        set {
            setBool(newValue, forKey: Keys.LongerbgMode)
        }
    }

    var showNotificationPreview: Bool {
        get {
            return boolForKey(Keys.ShowNotificationsPreview, defaultValue: true)
        }
        set {
            setBool(newValue, forKey: Keys.ShowNotificationsPreview)
        }
    }

    enum AutodownloadImages: String {
        case Never
        case UsingWiFi
        case Always
    }

    var autodownloadImages: AutodownloadImages {
        get {
            let defaultValue = AutodownloadImages.Never //Easy enough to reach option for users. Reverting change since there is an extremely high risk of people getting in trouble since an attacked can get you in prison by sending you cp.

            guard let string = stringForKey(Keys.AutodownloadImages) else {
                return defaultValue
            }
            return AutodownloadImages(rawValue: string) ?? defaultValue
        }
        set {
            setObject(newValue.rawValue as AnyObject?, forKey: Keys.AutodownloadImages)
        }
    }

    func resetUDPEnabled() {
        removeObjectForKey(Keys.UDPEnabled)
    }
}

private extension UserDefaultsManager {
    struct Keys {
        static let LastActiveProfile = "user-info/last-active-profile"
        static let EchobotAdded = "user-info/echobot-added"
        static let DebugMode = "user-info/debug-mode"
        static let DateonmessageMode = "user-info/dateonmessage-mode"
        static let UDPEnabled = "user-info/udp-enabled"
        static let ShowNotificationsPreview = "user-info/snow-notification-preview"
        static let LongerbgMode = "user-info/longerbg-mode"
        static let AutodownloadImages = "user-info/autodownload-images"
    }

    func setObject(_ object: AnyObject?, forKey key: String) {
        let defaults = UserDefaults.standard
        defaults.set(object, forKey:key)
        defaults.synchronize()
    }

    func stringForKey(_ key: String) -> String? {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: key)
    }

    func setBool(_ value: Bool, forKey key: String) {
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }

    func boolForKey(_ key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard

        if let result = defaults.object(forKey: key) {
            return (result as AnyObject).boolValue
        }
        else {
            return defaultValue
        }
    }

    func removeObjectForKey(_ key: String) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }
}
