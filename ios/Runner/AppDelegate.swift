import app_links
import flutter_background_service_ios

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private var statusChannel: FlutterMethodChannel?

  override func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "dev.floriang.truppsapp.background.refresh"

    // Retrieve the link from parameters
    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      AppLinks.shared.handleLink(url: url)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Status-Änderungen von CarPlay an Flutter weiterleiten
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("dev.floriang.trupp_app.STATUS_CHANGED"),
      object: nil,
      queue: .main
    ) { [weak self] notification in
      if let status = notification.userInfo?["status"] as? Int {
        self?.statusChannel?.invokeMethod("statusChanged", arguments: ["status": status])
      }
    }
  }
}
