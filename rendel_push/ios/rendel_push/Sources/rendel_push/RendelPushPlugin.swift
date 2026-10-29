import Flutter
import Security
import UIKit
import UserNotifications

/// Rendel's push on iOS, straight to Apple (design/plans/push-channels.md §3):
/// no Firebase. It asks for permission, registers for remote notifications and
/// hands Dart the hex device token with what Rendel's server needs to send to
/// it: which of Apple's hosts the build's token belongs to (a debug build's is
/// sandbox), the bundle id, and the Team ID the build is signed with.
///
/// Taps: it becomes the notification center's delegate and passes every
/// notification that is not Rendel's to the delegate it found there, so the
/// app's own handling is untouched; where Flutter's app delegate is the
/// delegate, that already hands each notification to every plugin. A Rendel push tapped before Dart is
/// listening (the tap that launched the app) waits until Dart asks for it.
public class RendelPushPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  private let channel: FlutterMethodChannel
  private weak var previous: UNUserNotificationCenterDelegate?
  private var waitingForToken: [FlutterResult] = []
  private var launchTap: [String: Any]?
  private var dartListening = false
  /// Each tap once: a launching tap can come both in the launch options and to the delegate.
  private var delivered = Set<String>()

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "rendel/push", binaryMessenger: registrar.messenger())
    let instance = RendelPushPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    // The token arrives in the app delegate's callbacks, which Flutter passes on to plugins.
    registrar.addApplicationDelegate(instance)
    // A scene app registers plugins after launch; the tap that launched it is
    // in the scene's connection options. By name, so a Flutter from before
    // scene plugins still builds this.
    let addScene = NSSelectorFromString("addSceneDelegate:")
    if (registrar as AnyObject).responds(to: addScene) {
      _ = (registrar as AnyObject).perform(addScene, with: instance)
    }
    let center = UNUserNotificationCenter.current()
    // Flutter's own app delegate, as the delegate, passes each call to every
    // plugin, this one included: it stays.
    if !(center.delegate is FlutterAppLifeCycleProvider) && center.delegate !== instance {
      instance.previous = center.delegate
      center.delegate = instance
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "permission":
      let ask = (call.arguments as? [String: Any])?["ask"] as? Bool ?? true
      permission(ask: ask, result)
    case "token":
      token(result)
    case "launchTap":
      dartListening = true
      let tap = launchTap
      launchTap = nil
      result(tap.flatMap { first($0) ? $0 : nil })
    case "hasFirebase":
      result(false)
    case "package":
      result(Bundle.main.bundleIdentifier)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func permission(ask: Bool, _ result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      let allowed: (UNAuthorizationStatus) -> Bool = { status in
        if #available(iOS 14.0, *), status == .ephemeral { return true }
        return status == .authorized || status == .provisional
      }
      if allowed(settings.authorizationStatus) || !ask || settings.authorizationStatus == .denied {
        DispatchQueue.main.async { result(allowed(settings.authorizationStatus)) }
        return
      }
      center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    }
  }

  private func token(_ result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      self.waitingForToken.append(result)
      UIApplication.shared.registerForRemoteNotifications()
      // Apple answers within seconds or not at all (no network at first launch).
      DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
        guard !self.waitingForToken.isEmpty else { return }
        self.answerToken(FlutterError(code: "push_timeout", message: "Apple gave no device token within 15 seconds", details: nil))
      }
    }
  }

  private func answerToken(_ answer: Any?) {
    let waiting = waitingForToken
    waitingForToken.removeAll()
    for result in waiting { result(answer) }
  }

  // MARK: The token

  public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    var token: [String: Any] = [
      "token": deviceToken.map { String(format: "%02x", $0) }.joined(),
      "provider": "apns",
      "environment": Self.environment(),
    ]
    if let bundleId = Bundle.main.bundleIdentifier { token["bundleId"] = bundleId }
    if let teamId = Self.teamId() { token["teamId"] = teamId }
    if waitingForToken.isEmpty {
      // A token Apple changed on its own: Dart sends it again.
      channel.invokeMethod("token", arguments: token)
    } else {
      answerToken(token)
    }
  }

  public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    // Most often the build has no `aps-environment`: the Push Notifications capability is missing.
    answerToken(FlutterError(code: "push_register", message: error.localizedDescription, details: nil))
  }

  /// Which of Apple's hosts takes this build's token: the provisioning
  /// profile's `aps-environment`. Builds from the App Store and TestFlight
  /// carry no profile and are production; the simulator is sandbox.
  static func environment() -> String {
    #if targetEnvironment(simulator)
      return "sandbox"
    #else
      return (profile()?["Entitlements"] as? [String: Any])?["aps-environment"] as? String == "development" ? "sandbox" : "production"
    #endif
  }

  /// The embedded provisioning profile's plist, where there is one.
  private static func profile() -> [String: Any]? {
    guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
      let data = FileManager.default.contents(atPath: path),
      let text = String(data: data, encoding: .isoLatin1),
      let start = text.range(of: "<?xml"),
      let end = text.range(of: "</plist>")
    else { return nil }
    let plist = Data(text[start.lowerBound..<end.upperBound].utf8)
    return (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any]
  }

  /// The Team ID the build is signed with: the profile's, else the prefix of
  /// the keychain access group every app gets, which is the App ID prefix.
  static func teamId() -> String? {
    let valid: (String?) -> String? = { id in
      guard let id = id, id.count == 10, id.allSatisfy({ $0.isUppercase || $0.isNumber }) else { return nil }
      return id
    }
    if let team = valid((profile()?["TeamIdentifier"] as? [String])?.first) { return team }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "ai.rendel.push",
      kSecAttrAccount as String: "team",
      kSecReturnAttributes as String: true,
    ]
    var found: CFTypeRef?
    var status = SecItemCopyMatching(query as CFDictionary, &found)
    if status == errSecItemNotFound {
      var add = query
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(add as CFDictionary, &found)
    }
    guard status == errSecSuccess, let attributes = found as? [String: Any],
      let group = attributes[kSecAttrAccessGroup as String] as? String
    else { return nil }
    return valid(group.components(separatedBy: ".").first)
  }

  // MARK: Taps

  /// The tap that launched an app without scenes.
  public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]) -> Bool {
    if let userInfo = launchOptions[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any], Self.isRendel(userInfo) {
      launchTap = Self.strings(userInfo)
    }
    return true
  }

  /// The tap that launched a scene app (`FlutterSceneLifeCycleDelegate`).
  @objc(scene:willConnectToSession:options:)
  public func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions?) -> Bool {
    if let userInfo = options?.notificationResponse?.notification.request.content.userInfo, Self.isRendel(userInfo), !dartListening {
      launchTap = Self.strings(userInfo)
    }
    return false
  }

  private func first(_ data: [String: Any]) -> Bool {
    let id = data["rendel_followup"] as? String ?? data.description
    return delivered.insert(id).inserted
  }

  private static func isRendel(_ userInfo: [AnyHashable: Any]) -> Bool {
    (userInfo["rendel"] as? String) == "1"
  }

  private static func strings(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var data: [String: Any] = [:]
    for (key, value) in userInfo where key as? String != "aps" {
      if let key = key as? String, value is String { data[key] = value }
    }
    return data
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    guard Self.isRendel(userInfo) else {
      // Reached through Flutter's app delegate: the plugin it is for answers.
      if center.delegate !== self { return }
      if let previous = previous, previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
        previous.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
      } else {
        completionHandler()
      }
      return
    }
    let data = Self.strings(userInfo)
    if dartListening {
      if first(data) { channel.invokeMethod("tap", arguments: data) }
    } else {
      launchTap = data
    }
    completionHandler()
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard Self.isRendel(notification.request.content.userInfo) else {
      if center.delegate !== self { return }
      if let previous = previous, previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
        previous.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
      } else {
        completionHandler([])
      }
      return
    }
    // Rendel's push shows while the app is open too: it is news the person asked for.
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
    if #available(iOS 12.0, *) {
      previous?.userNotificationCenter?(center, openSettingsFor: notification)
    }
  }
}
