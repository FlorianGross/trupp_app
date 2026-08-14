# CarPlay / Android Auto

Status-Meldungen lassen sich direkt aus dem Fahrzeug-Display absetzen, ohne das
Telefon in die Hand zu nehmen. Beide Plattformen nutzen denselben MethodChannel
`dev.floriang.trupp_app/status`.

## Freigabe durch Apple

Die CarPlay-Kategorie **Public Safety**
(`com.apple.developer.carplay-public-safety`) ist von Apple freigegeben und dem
Developer-Account zugewiesen:

| | |
|---|---|
| Case-ID | 21199826 |
| Team-ID | KZMTDB6J48 |
| App-Typ | `PUBLIC_SAFETY` |
| Bundle-ID | `dev.floriang.truppsapp` |

Das Entitlement steht bereits in `ios/Runner/Runner.entitlements` und ist in
allen drei Build-Konfigurationen (Debug/Profile/Release) über
`CODE_SIGN_ENTITLEMENTS` verdrahtet.

### Was im Developer-Portal noch passieren muss

Diese Schritte sind **nicht** im Repository abbildbar und müssen einmalig im
Apple Developer Account gemacht werden — ohne sie schlägt das Signieren fehl
(„Provisioning profile doesn't include the
com.apple.developer.carplay-public-safety entitlement"):

1. Developer-Account → *Certificates, Identifiers & Profiles* → **Identifiers**
2. App-ID `dev.floriang.truppsapp` auswählen
3. CarPlay-Capability aktivieren, Kategorie **Public Safety** wählen, *Save*
4. Unter **Profiles** ein **neues** Provisioning-Profil für die App-ID erzeugen
   (bestehende Profile übernehmen das neue Entitlement nicht automatisch)
5. Profil in Xcode laden bzw. den CI-Build-Secret aktualisieren

## Aufbau iOS

- `ios/Runner/Info.plist` deklariert die Szene
  `CPTemplateApplicationSceneSessionRoleApplication` mit der Delegate-Klasse
  `$(PRODUCT_MODULE_NAME).TruppCarPlaySceneDelegate`.
- `ios/Runner/TruppCarPlaySceneDelegate.swift` baut ein `CPGridTemplate` mit den
  fahrrelevanten Status (1, 2, 3, 4, 6, 7, 8 — ohne Notruf/Sprechwunsch, die im
  Fahrbetrieb nicht sinnvoll bedienbar sind).
- App-Icons für CarPlay liegen als `AppIcon-60@2x~car.png` /
  `AppIcon-60@3x~car.png` im Asset-Katalog.

## Aufbau Android

- `TruppIotCarService` / `TruppIotScreen` (`androidx.car.app`, Kategorie `IOT`)
  zeigen die Status als `ListTemplate`.
- `MainActivity` überträgt zwischen Car-App und Flutter-Engine.

## Wer sendet den Status?

Die native Car-Schicht läuft auch dann, wenn die Flutter-Oberfläche nicht im
Vordergrund ist. Sie sendet den Status deshalb **selbst** an die Leitstelle
(ein Retry bei Netz-/5xx-Fehler) und meldet der App anschließend das Ergebnis:

```
Druck im Auto
   └─ native Übertragung an die Leitstelle
        └─ statusChanged { status, delivered }  →  Flutter
             ├─ delivered = true  → App übernimmt nur Historie/Anzeige/GPS
             └─ delivered = false → App sendet über StatusSyncManager nach
                                    (Offline-Queue inkl. SDS-Nachmeldung)
```

Das `delivered`-Flag ist wichtig: Ohne es würde die App jede im Auto gedrückte
Meldung ein zweites Mal senden und der Status stünde doppelt in der Leitstelle.
Fehlt das Flag (ältere native Schicht), wird es konservativ als `false`
behandelt — lieber einmal zu viel nachsenden als eine Statusmeldung verlieren.

Die Gegenrichtung (Status in der App gedrückt → Anzeige im Auto aktualisieren)
läuft über `IotCarHelper.sendStatusToIot` und ändert im Auto nur die Darstellung,
löst also keinen weiteren Versand aus.
