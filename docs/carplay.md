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

## Statusvorschlag bei Ankunft (Geofence)

Erreicht das Fahrzeug ein hinterlegtes Ziel, fragt das CarPlay-Display nach,
statt dass der Statuswechsel vergessen wird:

| Ziel | Vorschlag | Gesetzt über |
|---|---|---|
| Einsatzort | Status 4 (Ziel erreicht) | Pro → Einsatz-Detail → Zielsymbol in der Titelleiste |
| Wache | Status 2 (Einsatzbereit Wache) | Mehr → Einstellungen → *Wache* („Position übernehmen") |

```
Hintergrunddienst (Position)
   └─ ArrivalDetector.evaluate()
        └─ service.invoke('arrivalSuggestion')  →  UI-Isolate
             └─ IotCarHelper.showStatusSuggestion()  →  CPAlertTemplate
                  └─ „senden" → normaler Statusweg inkl. delivered-Flag
```

Gesendet wird nichts automatisch — bestätigt wird immer im Fahrzeug. Ein
Vorschlag entfällt, wenn der Status ohnehin schon gesetzt ist.

`ArrivalDetector` (`lib/data/arrival_detector.dart`) ist bewusst frei von
Plugin-Abhängigkeiten und in `test/arrival_detector_test.dart` abgedeckt. Er
sichert gegen die drei Fälle ab, die eine Ankunfts-Erkennung sonst unbrauchbar
machen:

- **Ungenaue Fixes** (> 100 m) werden verworfen — ein WLAN-Fix springt sonst in
  den Radius und löst während der Fahrt eine Rückfrage aus.
- **Start im Radius** ist keine Ankunft. Wer auf der Wache einschaltet, wird
  nicht gefragt; gemeldet wird nur eine echte Bewegung von außen nach innen.
- **Zappeln an der Radiusgrenze** wird über eine Hysterese abgefangen: erst
  deutlich außerhalb (Faktor 1,5) wird das Ziel wieder scharf gestellt.

Die Ziele liegen als JSON in den SharedPreferences, damit der Hintergrund-
Isolate sie lesen kann. Er puffert sie eine Minute; die UI meldet Änderungen
sofort über `arrivalTargetsChanged`.

**Grenzen:** Die Rückfrage erscheint nur im CarPlay-Display und nur, solange der
UI-Isolate der App lebt (der Hintergrunddienst kann keine Templates zeigen). Für
Android Auto ist die Rückfrage noch nicht umgesetzt — dort werden Ziele zwar
erkannt, aber nicht angezeigt.

## Einsatz-Liste („wer ist noch auf dem Einsatz?")

Der achte Grid-Button *Einsatz* öffnet eine Liste der Fahrzeuge, die mit dem
eigenen auf demselben Einsatz laufen — mit Status, Besatzung und Abschnitt. Das
eigene Fahrzeug steht oben und ist mit `▶` markiert.

**Der Einsatz wird nicht von Hand gewählt**, sondern von der Leitstelle
abgeleitet — sie weiß ohnehin, worauf disponiert ist:

```
eigene ISSI (Prefs)
  → getTetraEndgeraete()  → rufname des eigenen Geräts
    → getEinsatzmittel()  → einsatznummer des eigenen Fahrzeugs
      → alle Einsatzmittel mit derselben einsatznummer
```

Die Zuordnung ISSI→Rufname ändert sich praktisch nie und wird gepuffert; die
Einsatzmittel werden bei jeder Abfrage frisch geholt. Abgefragt wird **nur beim
Öffnen der Liste** (Holschuld) — kein Polling im Hintergrund, das im Fahrzeug
nur Akku und Funkzeit kosten würde.

Kommt keine Liste zustande, zeigt das Display den Grund im Klartext statt einer
leeren Liste („Keinem Einsatz zugeordnet", „Pro-API nicht konfiguriert",
„Leitstelle nicht erreichbar", „App nicht gestartet").

Die Auswertung steckt in `EinsatzCrewResolver` (`lib/data/einsatz_crew.dart`) —
reine Funktionen ohne HTTP, abgedeckt in `test/einsatz_crew_test.dart`. Die
CarPlay-Szene erreicht die Flutter-Engine über `TruppFlutterBridge`, weil sie in
einer eigenen Szene läuft und den MethodChannel des AppDelegate nicht kennt.

**Voraussetzung:** die Pro-API. Ohne sie gibt es keine Einsatzmittel-Daten, und
der Button meldet das entsprechend.

**Templatewahl:** bewusst eine gepushte `CPListTemplate` statt eines
`CPTabBarTemplate`. Die Public-Safety-Kategorie erlaubt eine Stack-Tiefe von 5,
das Pushen ist also gedeckt; welche Templates die Kategorie genau freigibt,
steht nur in der Tabelle auf Seite 15 des CarPlay App Programming Guide (PDF,
nicht frei abrufbar) — die restriktivere Tab-Bar-Variante wurde deshalb
vermieden.
