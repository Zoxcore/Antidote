// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit
import Firebase
import os

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let gcmMessageIDKey = "gcm.message_id"
    var coordinator: AppCoordinator!
    var backgroundTask: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame:UIScreen.main.bounds)

        if ProcessInfo.processInfo.arguments.contains("UI_TESTING") {
            // Speeding up animations for UI tests.
            window!.layer.speed = 1000
        }

        configureLoggingStuff()

        coordinator = AppCoordinator(window: window!)
        coordinator.startWithOptions(nil)

        if let notification = launchOptions?[UIApplicationLaunchOptionsKey.localNotification] as? UILocalNotification {
            coordinator.handleLocalNotification(notification)
        }

        window?.backgroundColor = UIColor.white
        window?.makeKeyAndVisible()

        FirebaseApp.configure()

        Messaging.messaging().delegate = self

        if #available(iOS 10.0, *) {
          UNUserNotificationCenter.current().delegate = self

          let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
          UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { _, _ in }
          )
        } else {
          let settings: UIUserNotificationSettings =
            UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
          application.registerUserNotificationSettings(settings)
        }

        application.registerForRemoteNotifications()
        // HINT: try to go online every 47 minutes
        let bgfetchInterval: TimeInterval = 47 * 60
        application.setMinimumBackgroundFetchInterval(bgfetchInterval);
        os_log("AppDelegate:didFinishLaunchingWithOptions")

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        print("WillTerminate")
        os_log("AppDelegate:applicationWillTerminate")
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        print("DidReceiveMemoryWarning")
        os_log("AppDelegate:applicationDidReceiveMemoryWarning")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("DidEnterBackground")
        os_log("AppDelegate:applicationDidEnterBackground:start")
        backgroundTask = UIApplication.shared.beginBackgroundTask (expirationHandler: { [unowned self] in
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = UIBackgroundTaskInvalid
            os_log("AppDelegate:applicationDidEnterBackground:end")
        })
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        print("performFetchWithCompletionHandler:start")
        os_log("AppDelegate:performFetchWithCompletionHandler:start")
        // HINT: we have 30 seconds here. use 25 of those 30 seconds to be on the safe side
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            completionHandler(UIBackgroundFetchResult.newData)
            print("performFetchWithCompletionHandler:end")
            os_log("AppDelegate:performFetchWithCompletionHandler:end")
        }
    }

    func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
        coordinator.handleLocalNotification(notification)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any]) -> Bool {
        coordinator.handleInboxURL(url)

        return true
    }

    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        coordinator.handleInboxURL(url)

        return true
    }

  // Device received notification (legacy callback)
  //
  func application(_ application: UIApplication,
                   didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
    if let messageID = userInfo[gcmMessageIDKey] {
      print("Message ID: \(messageID)")
    }
  }

  // tells the app that a remote notification arrived that indicates there is data to be fetched.
  // ios 7+
  //
  func application(_ application: UIApplication,
                   didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                   fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult)
                     -> Void) {
    if let messageID = userInfo[gcmMessageIDKey] {
      print("Message ID: \(messageID)")
    }

    os_log("AppDelegate:didReceiveRemoteNotification:start")
    // HINT: we have 30 seconds here. use 25 of those 30 seconds to be on the safe side
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
        completionHandler(UIBackgroundFetchResult.newData)
        os_log("AppDelegate:didReceiveRemoteNotification:start")
    }
  }

  // APNs failed to register the device for push notifications
  //
  func application(_ application: UIApplication,
                   didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Unable to register for remote notifications: \(error.localizedDescription)")
  }

  func application(_ application: UIApplication,
                   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("APNs token retrieved: \(deviceToken)")
    os_log("AppDelegate:didRegisterForRemoteNotificationsWithDeviceToken")
  }
}

@available(iOS 10, *)
extension AppDelegate: UNUserNotificationCenterDelegate {

  // determine what to do if app is in foreground when a notification is coming
  // ios 10+ UNUserNotificationCenterDelegate method
  //
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
                                -> Void) {
    let userInfo = notification.request.content.userInfo

    if let messageID = userInfo[gcmMessageIDKey] {
      print("Message ID: \(messageID)")
    }
    completionHandler([[.alert, .sound]])
  }

  // Process and handle the user's response to a delivered notification.
  // ios 10+ UNUserNotificationCenterDelegate method
  //
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo

    if let messageID = userInfo[gcmMessageIDKey] {
      print("Message ID: \(messageID)")
    }
    completionHandler()
  }

}

private extension AppDelegate {
    func configureLoggingStuff() {
        DDLog.add(DDASLLogger.sharedInstance())
        // DDLog.add(DDTTYLogger.sharedInstance())
    }
}

extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("Firebase registration token: \(String(describing: fcmToken))")

    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}
