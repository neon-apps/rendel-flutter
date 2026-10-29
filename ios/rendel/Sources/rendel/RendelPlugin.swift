import AVFoundation
import EventKit
import EventKitUI
import Flutter
import PassKit
import UIKit

#if canImport(rendel_pcm)
  import rendel_pcm
#endif

/// The copilot's native half on iOS: two things Flutter cannot do alone.
///
/// It tells the SDK which usage strings the host app's Info.plist is missing.
/// iOS terminates an app the moment it touches the microphone, the speech
/// recogniser or the camera without `NSMicrophoneUsageDescription`,
/// `NSSpeechRecognitionUsageDescription` or `NSCameraUsageDescription`, and no
/// package can add them: Apple shows them to the user in the app's name, so
/// they live in the app's own Info.plist. What the SDK can do is look before it
/// draws the control.
///
/// And it opens the Files app for the composer's Files tool. Here rather than
/// in a picker package because the packages that reach documents also link the
/// photo library and the music library, and App Review then asks every host
/// for purpose strings it never needed. The system document picker needs no
/// permission: the app only ever sees the one file somebody chose.
///
/// And it opens the system's event editor for an `add_to_calendar` button,
/// filled in, for the user to save or cancel. Since iOS 17 that editor runs
/// outside the app and needs no calendar permission, which is the only reason
/// it is here rather than in a calendar package that writes the event itself.
///
/// And it draws Apple's own "Add to Apple Wallet" button under a `pass` block,
/// `PKAddPassButton` as a platform view, which iOS draws in the user's
/// language and VoiceOver reads; a tap downloads the .pkpass and offers it in
/// `PKAddPassesViewController`, where the user adds it or does not. Apple asks
/// for its own button rather than a drawing of one, and the sheet needs no
/// entitlement: it is the user who adds the pass.
public class RendelPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate,
  EKEventEditViewDelegate
{
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "rendel/platform",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(RendelPlugin(), channel: channel)
    registrar.register(AddPassButtonFactory(), withId: "rendel/add-pass")
    // Reading aloud's PCM output, on its own channel.
    RendelPcmSound.register(with: registrar)
  }

  /// The answer owed to the picker that is open. One at a time.
  private var picking: FlutterResult?

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "missingUsageDescriptions":
      let keys = call.arguments as? [String] ?? []
      let info = Bundle.main.infoDictionary ?? [:]
      result(keys.filter { key in
        guard let value = info[key] as? String else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    case "pickDocument":
      pickDocument(result)
    case "addToCalendar":
      addToCalendar(call.arguments as? [String: Any] ?? [:], result)
    case "voiceSession":
      voiceSession(active: call.arguments as? Bool ?? false, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The answer read aloud owns the audio while it speaks, and gives it back
  /// after (Tuna 2026-10-23). Active: playback, so the silent switch does not
  /// mute it, spoken audio, and other apps' sound ducked under it. Inactive:
  /// the session is let go with a word to the others, so the music that was
  /// ducked comes back up. The PCM player sets a category but never lets go.
  private func voiceSession(active: Bool, _ result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      if active {
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
      } else {
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
      }
      result(nil)
    } catch {
      result(FlutterError(code: "audio_session", message: error.localizedDescription, details: nil))
    }
  }

  private func pickDocument(_ result: @escaping FlutterResult) {
    guard picking == nil else {
      result(FlutterError(code: "already_active", message: "a document picker is already open", details: nil))
      return
    }
    guard let presenter = Self.topController() else {
      result(FlutterError(code: "no_view", message: "nothing on screen to present the picker from", details: nil))
      return
    }
    // What the upload accepts, and nothing else: a HEIC from Files would be
    // picked, sent and refused. By identifier rather than `UTType`, which is
    // iOS 14 — the SDK supports 13. Import mode hands over a copy, so there
    // is no security scope to open.
    let picker = UIDocumentPickerViewController(
      documentTypes: [
        "com.adobe.pdf", "public.plain-text", "public.png", "public.jpeg",
        "org.webmproject.webp", "com.compuserve.gif",
      ],
      in: .import
    )
    picker.delegate = self
    picking = result
    presenter.present(picker, animated: true)
  }

  public func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else { return finish(nil) }
    do {
      let data = try Data(contentsOf: url)
      finish(["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: data)])
    } catch {
      finish(FlutterError(code: "unreadable", message: error.localizedDescription, details: nil))
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  private func finish(_ value: Any?) {
    let result = picking
    picking = nil
    result?(value)
  }

  private func addToCalendar(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let title = args["title"] as? String,
      let start = (args["starts_at"] as? NSNumber)?.doubleValue
    else {
      result(FlutterError(code: "bad_args", message: "an event needs a title and a start", details: nil))
      return
    }
    let present = {
      guard let presenter = Self.topController() else {
        result(FlutterError(code: "no_view", message: "nothing on screen to present the editor from", details: nil))
        return
      }
      let store = EKEventStore()
      let event = EKEvent(eventStore: store)
      event.title = title
      event.startDate = Date(timeIntervalSince1970: start / 1000)
      // An hour when no end was given, which is what the editor itself
      // offers for a new event.
      let end = (args["ends_at"] as? NSNumber)?.doubleValue
      event.endDate = end.map { Date(timeIntervalSince1970: $0 / 1000) } ?? event.startDate.addingTimeInterval(3600)
      event.location = args["location"] as? String
      event.notes = args["notes"] as? String
      let editor = EKEventEditViewController()
      editor.eventStore = store
      editor.event = event
      editor.editViewDelegate = self
      presenter.present(editor, animated: true)
      result(true)
    }
    if #available(iOS 17.0, *) {
      present()
      return
    }
    // Before iOS 17 the editor runs inside the app and needs full calendar
    // access, and iOS closes an app that asks for it without
    // NSCalendarsUsageDescription in its Info.plist. An app that has the line
    // gets the system's prompt first; one that does not gets no editor rather
    // than a crash.
    let usage = Bundle.main.infoDictionary?["NSCalendarsUsageDescription"] as? String ?? ""
    guard !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(FlutterError(
        code: "usage_description_missing",
        message: "before iOS 17 the event editor needs NSCalendarsUsageDescription in Info.plist",
        details: nil
      ))
      return
    }
    EKEventStore().requestAccess(to: .event) { granted, _ in
      DispatchQueue.main.async {
        if granted { present() } else { result(false) }
      }
    }
  }

  public func eventEditViewController(
    _ controller: EKEventEditViewController,
    didCompleteWith action: EKEventEditViewAction
  ) {
    controller.dismiss(animated: true)
  }

  /// Whatever is frontmost: the copilot is itself a sheet over the host's app.
  fileprivate static func topController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController ?? UIApplication.shared.delegate?.window??.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// Makes the `rendel/add-pass` platform view: one "Add to Apple Wallet"
/// button for the pass at the `url` it is created with.
final class AddPassButtonFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let url = (args as? [String: Any])?["url"] as? String
    return AddPassButton(frame: frame, url: url.flatMap { URL(string: $0) })
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Apple's button, and what a tap on it does: fetch the pass, then offer it.
/// The pass is the user's to add; nothing is added for them, and the copilot
/// hears nothing of it.
final class AddPassButton: NSObject, FlutterPlatformView {
  private let button = PKAddPassButton(addPassButtonStyle: .black)
  private let url: URL?

  init(frame: CGRect, url: URL?) {
    self.url = url
    super.init()
    button.frame = frame
    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    button.addTarget(self, action: #selector(add), for: .touchUpInside)
  }

  func view() -> UIView { button }

  @objc private func add() {
    // https only, as every link on the wire is; and one fetch at a time, so
    // a second tap while the pass is on its way does not offer it twice.
    guard let url = url, url.scheme == "https", button.isEnabled else { return }
    button.isEnabled = false
    URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.button.isEnabled = true
        // A pass that did not come, or is not one, offers nothing: there is
        // no sheet to show for it, and the button is there to tap again.
        guard let data = data,
          (response as? HTTPURLResponse)?.statusCode == 200,
          let pass = try? PKPass(data: data),
          let sheet = PKAddPassesViewController(pass: pass),
          let presenter = RendelPlugin.topController()
        else { return }
        presenter.present(sheet, animated: true)
      }
    }.resume()
  }
}
