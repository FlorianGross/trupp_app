import app_links
import flutter_background_service_ios

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var statusChannel: FlutterMethodChannel?

  override func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "dev.floriang.truppsapp.background.refresh"
    GeneratedPluginRegistrant.register(with: self)

    // MethodChannel für Car-Integration (Android Auto / CarPlay)
    if let controller = window?.rootViewController as? FlutterViewController {
      statusChannel = FlutterMethodChannel(
        name: "dev.floriang.trupp_app/status",
        binaryMessenger: controller.binaryMessenger
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

    // Retrieve the link from parameters
    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      AppLinks.shared.handleLink(url: url)
      return true
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // CarPlay-Scene programmatisch registrieren
  // HINWEIS: TruppCarPlaySceneDelegate.swift muss noch über Xcode zum Projekt hinzugefügt werden
  // (Rechtsklick Runner → Add Files to "Runner" → TruppCarPlaySceneDelegate.swift auswählen)
  override func application(
      _ application: UIApplication,
      configurationForConnecting connectingSceneSession: UISceneSession,
      options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    if let delegateClass = NSClassFromString("Runner.TruppCarPlaySceneDelegate") as? UIResponder.Type,
       connectingSceneSession.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" {
      let config = UISceneConfiguration(
        name: "TruppCarPlay",
        sessionRole: connectingSceneSession.role
      )
      config.delegateClass = delegateClass
      return config
    }
    return UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
  }
}
