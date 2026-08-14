import Foundation

/// Verbindung von der CarPlay-Szene zur Flutter-Engine.
///
/// Beide leben in getrennten Szenen: Die `CPTemplateApplicationSceneDelegate`
/// hat keinen Zugriff auf den `FlutterMethodChannel`, den der AppDelegate
/// aufsetzt. Statt den Channel durchzureichen, hinterlegt der AppDelegate hier
/// einen Closure, sobald die Engine läuft.
///
/// Ist der Closure nil, läuft keine Engine (App nicht gestartet) — die Szene
/// zeigt dann einen Hinweis statt einer leeren Liste.
///
/// Nur vom Main-Thread benutzen: Sowohl der Engine-Start als auch die
/// CarPlay-Callbacks laufen dort.
final class TruppFlutterBridge {
    static let shared = TruppFlutterBridge()
    private init() {}

    /// Fragt die am aktuellen Einsatz beteiligten Fahrzeuge bei Flutter ab.
    /// Liefert nil, wenn die Engine nicht erreichbar ist.
    var requestEinsatzCrew: ((@escaping ([String: Any]?) -> Void) -> Void)?
}
