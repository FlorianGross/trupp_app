import CarPlay
import UIKit

/// CarPlay Scene Delegate - Status-Buttons im Auto-Display
@available(iOS 14.0, *)
class TruppCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    // Status-Definitionen (ohne 0, 5, 9 – nur fahrrelevante Status)
    private let statusMap: [(num: Int, text: String, sfSymbol: String, color: UIColor)] = [
        (1, "Einsatzbereit", "antenna.radiowaves.left.and.right", .systemGreen),
        (2, "Wache", "house.fill", .systemBlue),
        (3, "Auftrag", "checkmark.rectangle.fill", .systemOrange),
        (4, "Ziel erreicht", "mappin.circle.fill", .systemPurple),
        (6, "Nicht bereit", "nosign", .systemGray),
        (7, "Transport", "shippingbox.fill", .systemIndigo),
        (8, "Angekommen", "flag.fill", .systemPink),
    ]

    private var currentStatus: Int = 1

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        // Aktuellen Status aus SharedPreferences laden
        loadCurrentStatus()

        // Grid-Template anzeigen
        let grid = buildGridTemplate()
        interfaceController.setRootTemplate(grid, animated: false, completion: nil)

        // Für Status-Updates vom Flutter-Teil registrieren
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
    }

    // MARK: - Grid Template

    private func buildGridTemplate() -> CPGridTemplate {
        var buttons: [CPGridButton] = []

        for entry in statusMap {
            let isActive = entry.num == currentStatus
            let image = createStatusImage(
                sfSymbol: entry.sfSymbol,
                color: entry.color,
                active: isActive
            )

            let button = CPGridButton(
                titleVariants: ["\(entry.num) \(entry.text)"],
                image: image
            ) { [weak self] _ in
                self?.onStatusPressed(entry.num)
            }

            buttons.append(button)
        }

        let template = CPGridTemplate(title: "Trupp Status", gridButtons: buttons)
        return template
    }

    private func createStatusImage(sfSymbol: String, color: UIColor, active: Bool) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        guard let symbol = UIImage(systemName: sfSymbol, withConfiguration: config) else {
            // Fallback: farbiger Kreis falls Symbol nicht verfügbar
            let size = CGSize(width: 44, height: 44)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                color.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
        }

        let tintColor = active ? color : color.withAlphaComponent(0.4)
        return symbol.withTintColor(tintColor, renderingMode: .alwaysOriginal)
    }

    // MARK: - Status Handling

    private func onStatusPressed(_ status: Int) {
        currentStatus = status
        saveCurrentStatus(status)

        // Grid aktualisieren
        let grid = buildGridTemplate()
        interfaceController?.setRootTemplate(grid, animated: false, completion: nil)

        // Status an Flutter senden via NotificationCenter
        NotificationCenter.default.post(
            name: NSNotification.Name("dev.floriang.trupp_app.STATUS_CHANGED"),
            object: nil,
            userInfo: ["status": status]
        )

        // HTTP-Request direkt senden (wie Android Auto)
        sendStatusToServer(status)
    }

    @objc private func onStatusUpdateFromFlutter(_ notification: Notification) {
        guard let status = notification.userInfo?["status"] as? Int,
              status >= 0, status <= 9 else { return }
        currentStatus = status

        // Grid aktualisieren
        let grid = buildGridTemplate()
        interfaceController?.setRootTemplate(grid, animated: false, completion: nil)
    }

    // MARK: - HTTP API

    private func sendStatusToServer(_ status: Int) {
        let defaults = UserDefaults.standard
        let protocol_ = defaults.string(forKey: "flutter.protocol") ?? "https"
        let server = defaults.string(forKey: "flutter.server") ?? ""
        let token = defaults.string(forKey: "flutter.token") ?? ""
        let issi = defaults.string(forKey: "flutter.issi") ?? ""

        guard !server.isEmpty, !token.isEmpty, !issi.isEmpty else { return }

        let urlString = "\(protocol_)://\(server)/\(token)/setstatus?issi=\(issi)&status=\(status)"
        guard let url = URL(string: urlString) else { return }

        let task = URLSession.shared.dataTask(with: url) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    self?.currentStatus = status
                    self?.saveCurrentStatus(status)
                }
            }
        }
        task.resume()
    }

    // MARK: - Persistence (SharedPreferences-kompatibel)

    private func loadCurrentStatus() {
        let defaults = UserDefaults.standard
        // Flutter SharedPreferences nutzt "flutter." Prefix
        currentStatus = defaults.integer(forKey: "flutter.lastStatus")
        if currentStatus == 0 && defaults.object(forKey: "flutter.lastStatus") == nil {
            currentStatus = 1  // Default: Einsatzbereit
        }
    }

    private func saveCurrentStatus(_ status: Int) {
        let defaults = UserDefaults.standard
        defaults.set(status, forKey: "flutter.lastStatus")
    }
}
