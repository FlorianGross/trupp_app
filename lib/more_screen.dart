import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'ConfigScreen.dart';
import 'data/app_prefs.dart';
import 'data/auto_delete_config.dart';
import 'data/duty_end_config.dart';
import 'data/gpx_exporter.dart';
import 'data/profile_store.dart';
import 'dienstanmeldung_screen.dart';
import 'onboarding_screen.dart';
import 'service.dart' show stopBackgroundServiceCompletely;
import 'main.dart' show themeNotifier, toggleTheme;
import 'utils/formatters.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'profiles_screen.dart';
import 'pro/pro_dashboard_screen.dart';
import 'staerke_editor_screen.dart';
import 'system_check_screen.dart';
import 'theme/brand_colors.dart';
import 'unit_type_picker_screen.dart';

/// Sammelt alle Aktionen, die früher hinter dem 3-Punkte-Menü versteckt waren.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  int _autoDeactivateMinutes = 0;
  String _activeProfileName = '';
  bool _wakelockInDeployment = true;
  bool _highFrequencyTracking = true;
  bool _preciseLocationOnly = true;
  DateTime? _autoDeleteAt;
  DateTime? _dutyEndAt;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final active = await ProfileStore.activeName() ?? '';
    final autoDeleteAt = await AutoDeleteConfig.scheduledAt();
    final dutyEndAt = await DutyEndConfig.scheduledAt();
    if (!mounted) return;
    setState(() {
      _autoDeactivateMinutes = prefs.getInt('autoDeactivateMinutes') ?? 0;
      _activeProfileName = active;
      _wakelockInDeployment =
          prefs.getBool(AppPrefsKeys.wakelockInDeployment) ?? true;
      _highFrequencyTracking =
          prefs.getBool(AppPrefsKeys.highFrequencyTracking) ?? true;
      _preciseLocationOnly =
          prefs.getBool(AppPrefsKeys.preciseLocationOnly) ?? true;
      _autoDeleteAt = autoDeleteAt;
      _dutyEndAt = dutyEndAt;
    });
  }

  /// Weist den laufenden Hintergrunddienst an, geänderte Tracking-
  /// Einstellungen sofort zu übernehmen (Stream + Filter neu aufsetzen).
  Future<void> _notifyServiceTrackingPrefsChanged() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('updateTrackingPrefs');
    }
  }

  Future<void> _setHighFrequencyTracking(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppPrefsKeys.highFrequencyTracking, value);
    if (!mounted) return;
    setState(() => _highFrequencyTracking = value);
    await _notifyServiceTrackingPrefsChanged();
  }

  Future<void> _setPreciseLocationOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppPrefsKeys.preciseLocationOnly, value);
    if (!mounted) return;
    setState(() => _preciseLocationOnly = value);
    await _notifyServiceTrackingPrefsChanged();
  }

  /// „Einsatz beenden": stoppt die Übertragung und löscht Konfiguration,
  /// Zugangsdaten und Einstellungen — die App startet danach wieder in der
  /// Einrichtung. Bewusst destruktiv, daher mit Rückfrage.
  Future<void> _endDeploymentAndWipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Einsatz beenden?'),
        content: const Text(
          'Die Standortübertragung wird gestoppt und ALLE Einstellungen sowie '
          'die Konfiguration (Server, Token, ISSI, Zugangsdaten, Profile) '
          'werden gelöscht.\n\nDas lässt sich nicht rückgängig machen — die App '
          'startet danach in der Einrichtung.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Beenden & löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 1) Laufenden Hintergrunddienst stoppen (Tracking aus, Service beenden),
    //    bevor die Konfiguration entfernt wird.
    try {
      await stopBackgroundServiceCompletely();
    } catch (_) {/* Service lief evtl. nicht — ignorieren */}

    // 2) Geplante Automatiken abbestellen (sonst greifen sie ins Leere).
    await AutoDeleteConfig.cancel();
    await DutyEndConfig.cancel();

    // 3) Konfiguration, Zugangsdaten und Einsatz-Zustand löschen.
    await AutoDeleteConfig.wipeNow();

    if (!mounted) return;

    // 4) Zurück in die Einrichtung, Navigations-Stack leeren.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (_) => false,
    );
  }

  Future<void> _setWakelockInDeployment(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppPrefsKeys.wakelockInDeployment, value);
    if (!mounted) return;
    setState(() => _wakelockInDeployment = value);
    // Sofort wirksam falls aktuell ein Wakelock aktiv ist (Einsatz läuft):
    // dann hier disable() abrufen. Wenn nicht aktiv, ist disable() ein No-Op.
    // enable() rufen wir nicht ungefragt — nur _loadDeploymentState() im
    // StatusOverview entscheidet bei Deployment-Start, ob enable nötig ist.
    if (!value) {
      await WakelockPlus.disable();
    }
  }

  void _showSnackbar(String msg, {bool success = true}) {
    final brand = Theme.of(context).brand;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? brand.success : brand.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportGpx() async {
    try {
      final path = await GpxExporter.exportAllFixesToGpx();
      await Share.shareXFiles([XFile(path)], text: 'GPX-Export');
    } catch (e) {
      _showSnackbar('Export fehlgeschlagen: $e', success: false);
    }
  }

  Future<void> _showAutoDeactivateDialog() async {
    const options = [
      (0, 'Aus'),
      (30, '30 Minuten'),
      (60, '1 Stunde'),
      (120, '2 Stunden'),
      (240, '4 Stunden'),
      (480, '8 Stunden'),
    ];

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Automatische Abmeldung'),
        children: options.map((opt) {
          final (minutes, label) = opt;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, minutes),
            child: Row(
              children: [
                Radio<int>(
                  value: minutes,
                  groupValue: _autoDeactivateMinutes,
                  onChanged: (_) => Navigator.pop(ctx, minutes),
                ),
                Text(label),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (selected == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('autoDeactivateMinutes', selected);
    setState(() => _autoDeactivateMinutes = selected);
    final msg = selected == 0
        ? 'Automatische Abmeldung deaktiviert'
        : 'Automatische Abmeldung nach ${selected >= 60 ? '${selected ~/ 60}h' : '${selected}min'} Inaktivität';
    _showSnackbar(msg, success: true);
  }

  String _autoDeleteSubtitle() {
    if (_autoDeleteAt == null) return 'Aus';
    return 'Löscht am ${fmtDateTime(_autoDeleteAt!)} Uhr';
  }

  String _dutyEndSubtitle() {
    if (_dutyEndAt == null) return 'Aus';
    return 'Abmeldung am ${fmtDateTime(_dutyEndAt!)} Uhr';
  }

  /// Dienstende festlegen: automatische Abmeldung (Übertragung stoppen, Einsatz
  /// beenden) nach X Stunden oder zu einer festen Uhrzeit.
  Future<void> _showDutyEndDialog() async {
    const hourOptions = [4, 6, 8, 10, 12];
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Dienstende (automatische Abmeldung)'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Aus'),
          ),
          const Divider(),
          for (final h in hourOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: Text('Nach $h Stunden'),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('Zu bestimmter Uhrzeit…'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 0) {
      await DutyEndConfig.cancel();
      await _loadState();
      if (!mounted) return;
      _showSnackbar('Automatische Abmeldung deaktiviert', success: true);
      return;
    }

    if (choice == -1) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        helpText: 'Dienstende wählen',
      );
      if (time == null || !mounted) return;
      await DutyEndConfig.scheduleAtTime(time.hour, time.minute);
    } else {
      await DutyEndConfig.scheduleAfterHours(choice);
    }

    await _loadState();
    if (!mounted) return;
    final at = _dutyEndAt;
    _showSnackbar(
      at != null
          ? 'Dienstende: automatische Abmeldung am ${fmtDateTime(at)} Uhr'
          : 'Dienstende aktiviert',
      success: true,
    );
  }

  /// Auswahl-Dialog für AutoDelete: Konfiguration nach X Stunden oder zu einer
  /// festen Uhrzeit automatisch löschen (Gerät zurück auf Einrichtung).
  Future<void> _showAutoDeleteDialog() async {
    // Rückgabewerte: 0 = Aus, >0 = Stunden, -1 = Uhrzeit wählen.
    const hourOptions = [1, 2, 4, 8, 12, 24];

    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Konfiguration automatisch löschen'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Aus'),
          ),
          const Divider(),
          for (final h in hourOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: Text('Nach $h ${h == 1 ? 'Stunde' : 'Stunden'}'),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('Zu bestimmter Uhrzeit…'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 0) {
      await AutoDeleteConfig.cancel();
      await _loadState();
      if (!mounted) return;
      _showSnackbar('Automatisches Löschen deaktiviert', success: true);
      return;
    }

    if (choice == -1) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        helpText: 'Löschzeitpunkt wählen',
      );
      if (time == null || !mounted) return;
      await AutoDeleteConfig.scheduleAtTime(time.hour, time.minute);
    } else {
      await AutoDeleteConfig.scheduleAfterHours(choice);
    }

    await _loadState();
    if (!mounted) return;
    final at = _autoDeleteAt;
    _showSnackbar(
      at != null
          ? 'Konfiguration wird am ${fmtDateTime(at)} Uhr gelöscht'
          : 'Automatisches Löschen aktiviert',
      success: true,
    );
  }

  Future<void> _changeUnitType() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            UnitTypePickerScreen(allowBack: true, onComplete: null),
      ),
    );
  }

  Future<void> _openProfiles() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilesScreen()),
    );
    await _loadState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mehr'),
        elevation: 0,
        centerTitle: true,
      ),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (_, themeMode, __) {
          final isDark = themeMode == ThemeMode.dark;
          return ListView(
            children: [
              _sectionHeader('Meldungen'),
              _tile(
                icon: Icons.how_to_reg,
                title: 'Dienstanmeldung',
                subtitle: 'Team, Qualifikationen & Stärke ans ELW melden',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DienstanmeldungScreen()),
                ),
              ),
              _tile(
                icon: Icons.assignment_ind,
                title: 'Stärkemeldung',
                subtitle: 'Eigene Stärke an die Leitstelle übermitteln',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const StaerkeEditorScreen()),
                ),
              ),
              _tile(
                icon: Icons.download,
                title: 'GPX-Export',
                subtitle: 'Alle Positionen als GPX-Datei teilen',
                onTap: _exportGpx,
              ),

              _sectionHeader('Einstellungen'),
              _tile(
                icon: Icons.settings,
                title: 'Konfiguration',
                subtitle: 'Server, Token, ISSI, Pro-API',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConfigScreen()),
                ),
              ),
              _tile(
                icon: Icons.switch_account,
                title: 'Konfigurationsprofile',
                subtitle: _activeProfileName.isNotEmpty
                    ? 'Aktiv: $_activeProfileName'
                    : 'Mehrere Server-Profile verwalten',
                onTap: _openProfiles,
              ),
              _tile(
                icon: Icons.swap_horiz,
                title: 'Einheitstyp ändern',
                subtitle: 'Status-Tasten an die Einheit anpassen',
                onTap: _changeUnitType,
              ),
              _tile(
                icon: Icons.timer_off,
                title: 'Automatische Abmeldung',
                subtitle: _autoDeactivateMinutes == 0
                    ? 'Aus'
                    : 'Nach ${_autoDeactivateMinutes >= 60 ? '${_autoDeactivateMinutes ~/ 60}h' : '${_autoDeactivateMinutes}min'} Inaktivität',
                onTap: _showAutoDeactivateDialog,
              ),
              _tile(
                icon: Icons.event_busy,
                title: 'Dienstende',
                subtitle: _dutyEndSubtitle(),
                onTap: _showDutyEndDialog,
              ),
              _tile(
                icon: Icons.auto_delete,
                title: 'Konfiguration automatisch löschen',
                subtitle: _autoDeleteSubtitle(),
                onTap: _showAutoDeleteDialog,
              ),
              _tile(
                icon: isDark ? Icons.light_mode : Icons.dark_mode,
                title: isDark ? 'Helles Design' : 'Dunkles Design',
                subtitle: 'Erscheinungsbild umschalten',
                onTap: toggleTheme,
              ),
              SwitchListTile(
                secondary: Icon(Icons.screen_lock_portrait,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text(
                  'Display im Einsatz wachhalten',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: const Text(
                  'Sinnvoll am Halter im Fahrzeug. In der Tasche '
                  'akku-sparend besser ausschalten.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _wakelockInDeployment,
                onChanged: _setWakelockInDeployment,
              ),
              SwitchListTile(
                secondary: Icon(Icons.speed,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text(
                  'Hohe Standort-Frequenz',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: const Text(
                  'Häufigere Positionsübertragung (kürzere Intervalle, '
                  'engere Distanz). Genauer, aber mehr Akkuverbrauch. '
                  'Aktive Status (1/3/7) werden ohnehin dicht getrackt.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _highFrequencyTracking,
                onChanged: _setHighFrequencyTracking,
              ),
              SwitchListTile(
                secondary: Icon(Icons.gps_fixed,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text(
                  'Nur präziser Standort',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: const Text(
                  'Ungenaue WLAN-/Funkzellen-Ortung verwerfen und nur '
                  'GPS-genaue Standorte senden. Ausschalten, wenn ein grober '
                  'Standort besser ist als gar keiner.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _preciseLocationOnly,
                onChanged: _setPreciseLocationOnly,
              ),

              _sectionHeader('Diagnose'),
              _tile(
                icon: Icons.health_and_safety,
                title: 'Systemprüfung',
                subtitle: 'Berechtigungen, GPS, Hintergrunddienst prüfen',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SystemCheckScreen()),
                ),
              ),
              _tile(
                icon: Icons.workspace_premium,
                title: 'Pro-Funktionen',
                subtitle: 'Einsatzliste, EDP-Bestand, ISSI-Auswahl',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ProDashboardScreen()),
                ),
              ),

              _sectionHeader('Einsatz'),
              ListTile(
                leading: Icon(Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error),
                title: Text(
                  'Einsatz beenden & alles löschen',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                subtitle: const Text(
                  'Übertragung stoppen und Konfiguration, Zugangsdaten und '
                  'Einstellungen löschen. Das Gerät startet danach in der '
                  'Einrichtung.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right,
                    color: Theme.of(context).colorScheme.error),
                onTap: _endDeploymentAndWipe,
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Icon(Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
