import app_links
import flutter_background_service_ios
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private var statusChannel: FlutterMethodChannel?

  override func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "dev.floriang.truppsapp.background.refresh"

    // Delegate setzen, damit Notifications auch im Vordergrund angezeigt werden
    // und damit flutter_local_notifications Tap-Events korrekt empfängt.
    UNUserNotificationCenter.current().delegate = self

    // Retrieve the link from parameters
    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      AppLinks.shared.handleLink(url: url)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Wenn die App im Vordergrund ist: Notification trotzdem als Banner + Ton anzeigen
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound, .badge])
  }

  // Wird aufgerufen sobald der Flutter-Engine initialisiert ist (UIScene-Lifecycle)
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // MethodChannel für Car-Integration (Android Auto / CarPlay)
    let messenger = engineBridge.applicationRegistrar.messenger()
    statusChannel = FlutterMethodChannel(
      name: "dev.floriang.trupp_app/status",
      binaryMessenger: messenger
    )

    // Calls von Flutter empfangen (sendStatusToIot)
    statusChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "sendStatusToIot",
         let args = call.arguments as? [String: Any],
         let status = args["status"] as? Int {
        // Status an CarPlay weiterleiten via NotificationCenter
        NotificationCenter.default.post(
          name: NSNotification.Name("dev.floriang.trupp_app.STATUS_UPDATE"),
          object: nil,
          userInfo: ["status": status]
        )
        result(true)
      } else if call.method == "showStatusSuggestion",
                let args = call.arguments as? [String: Any],
                let status = args["status"] as? Int {
        // Ankunfts-Rückfrage im CarPlay-Display anzeigen lassen.
        NotificationCenter.default.post(
          name: NSNotification.Name("dev.floriang.trupp_app.STATUS_SUGGESTION"),
          object: nil,
          userInfo: ["status": status, "label": args["label"] as? String ?? ""]
        )
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Die CarPlay-Szene kann die Flutter-Engine nicht direkt erreichen — sie
    // fragt die Einsatz-Liste über diese Brücke ab.
    TruppFlutterBridge.shared.requestEinsatzCrew = { [weak self] completion in
      guard let channel = self?.statusChannel else {
        completion(nil)
        return
      }
      channel.invokeMethod("getEinsatzCrew", arguments: nil) { result in
        completion(result as? [String: Any])
      }
    }

    // Status-Änderungen von CarPlay an Flutter weiterleiten
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("dev.floriang.trupp_app.STATUS_CHANGED"),
      object: nil,
      queue: .main
    ) { [weak self] notification in
      if let status = notification.userInfo?["status"] as? Int {
        // delivered: hat die CarPlay-Szene den Status schon zugestellt? Fehlt
        // das Flag, konservativ als "nein" behandeln — dann sendet die App über
        // ihre Queue nach, statt die Meldung zu verlieren.
        let delivered = notification.userInfo?["delivered"] as? Bool ?? false
        self?.statusChannel?.invokeMethod(
          "statusChanged",
          arguments: ["status": status, "delivered": delivered]
        )
      }
    }
  }
}
