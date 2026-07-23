import CarPlay
import UIKit

/// CarPlay Scene Delegate – Status-Buttons im Auto-Display
@available(iOS 14.0, *)
class TruppCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var gridTemplate: CPGridTemplate?

    // Fahrrelevante Status (ohne 0/Notruf, 5/Sprechwunsch, 9/Sonstiges)
    private let statusList: [(num: Int, text: String, sfSymbol: String, color: UIColor)] = [
        (1, "Einsatzbereit", "antenna.radiowaves.left.and.right", .systemGreen),
        (2, "Wache",         "house.fill",                        .systemBlue),
        (3, "Auftrag",       "checkmark.rectangle.fill",          .systemOrange),
        (4, "Ziel erreicht", "mappin.circle.fill",                .systemPurple),
        (6, "Nicht bereit",  "nosign",                            .systemGray),
        (7, "Transport",     "shippingbox.fill",                  .systemIndigo),
        (8, "Angekommen",    "flag.fill",                         .systemPink),
    ]

    private var currentStatus: Int = 1
    private var connectionOk: Bool? = nil   // nil=unbekannt, true=OK, false=Fehler
    private var currentTitle: String = ""   // zuletzt gesetzter Grid-Titel

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        loadCurrentStatus()

        let template = makeGridTemplate()
        gridTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onStatusUpdateFromFlutter(_:)),
            name: NSNotification.Name("dev.floriang.trupp_app.STATUS_UPDATE"),
            object: nil
        )
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        NotificationCenter.default.removeObserver(self)
        self.interfaceController = nil
        gridTemplate = nil
    }

    // MARK: - Template Building

    private func makeGridTemplate() -> CPGridTemplate {
        let buttons = buildButtons()
        let title = templateTitle()
        currentTitle = title
        let template = CPGridTemplate(title: title, gridButtons: buttons)
        return template
    }

    private func buildButtons() -> [CPGridButton] {
        statusList.map { entry in
            let isActive = entry.num == currentStatus
            let image = makeIcon(sfSymbol: entry.sfSymbol, color: entry.color, active: isActive)
            return CPGridButton(
                titleVariants: ["\(entry.num) \(entry.text)"],
                image: image
            ) { [weak self] _ in
                self?.onStatusPressed(entry.num)
            }
        }
    }

    private func templateTitle() -> String {
        let indicator: String
        switch connectionOk {
        case true:  indicator = "●"
        case false: indicator = "✗"
        default:    indicator = "○"
        }
        return "Trupp Status \(indicator)"
    }

    private func refreshTemplate() {
        let buttons = buildButtons()
        let title = templateTitle()

        // Button-Zustand (aktiver Status) lässt sich auf iOS 15+ ohne Template-
        // Austausch aktualisieren → kein Flackern. Nur wenn sich der Titel ändert
        // (Verbindungsanzeige), muss das Root-Template ersetzt werden — das ist
        // selten (nur bei Verbindungs-Zustandswechsel).
        if #available(iOS 15.0, *), title == currentTitle, let grid = gridTemplate {
            grid.updateGridButtons(buttons)
            return
        }
        currentTitle = title
        let newGrid = CPGridTemplate(title: title, gridButtons: buttons)
        gridTemplate = newGrid
        interfaceController?.setRootTemplate(newGrid, animated: false, completion: nil)
    }

    // MARK: - Status Handling

    private func onStatusPressed(_ status: Int) {
        // Optimistisch UI aktualisieren
        currentStatus = status
        refreshTemplate()

        // An Flutter melden (für die Haupt-App)
        NotificationCenter.default.post(
            name: NSNotification.Name("dev.floriang.trupp_app.STATUS_CHANGED"),
            object: nil,
            userInfo: ["status": status]
        )

        sendStatusToServer(status)
    }

    @objc private func onStatusUpdateFromFlutter(_ notification: Notification) {
        guard let status = notification.userInfo?["status"] as? Int,
              statusList.contains(where: { $0.num == status }) else { return }
        currentStatus = status
        DispatchQueue.main.async { [weak self] in self?.refreshTemplate() }
    }

    // MARK: - HTTP

    private func sendStatusToServer(_ status: Int) {
        let defaults = UserDefaults.standard
        let proto  = defaults.string(forKey: "flutter.protocol") ?? "https"
        let server = defaults.string(forKey: "flutter.server")   ?? ""
        let token  = defaults.string(forKey: "flutter.token")    ?? ""
        let issi   = defaults.string(forKey: "flutter.issi")     ?? ""

        guard !server.isEmpty, !token.isEmpty, !issi.isEmpty,
              let url = URL(string: "\(proto)://\(server)/\(token)/setstatus?issi=\(issi)&status=\(status)")
        else {
            connectionOk = false
            DispatchQueue.main.async { [weak self] in self?.refreshTemplate() }
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] _, response, error in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200..<300).contains(code)
            DispatchQueue.main.async {
                self.connectionOk = ok
                if ok {
                    self.saveCurrentStatus(status)
                }
                self.refreshTemplate()
            }
        }.resume()
    }

    // MARK: - Icon

    private func makeIcon(sfSymbol: String, color: UIColor, active: Bool) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let tintColor = active ? color : color.withAlphaComponent(0.35)
        if let symbol = UIImage(systemName: sfSymbol, withConfiguration: config) {
            return symbol.withTintColor(tintColor, renderingMode: .alwaysOriginal)
        }
        // Fallback: farbiger Kreis
        let size = CGSize(width: 44, height: 44)
        return UIGraphicsImageRenderer(size: size).image { _ in
            tintColor.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
    }

    // MARK: - Persistence

    private func loadCurrentStatus() {
        let defaults = UserDefaults.standard
        let saved = defaults.integer(forKey: "flutter.lastStatus")
        // integer(forKey:) returns 0 when key is missing — use status 1 as default
        currentStatus = (saved > 0) ? saved : 1
    }

    private func saveCurrentStatus(_ status: Int) {
        UserDefaults.standard.set(status, forKey: "flutter.lastStatus")
    }
}
