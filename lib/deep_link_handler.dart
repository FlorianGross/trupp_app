import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'ConfigScreen.dart';
import 'data/edp_api.dart';
import 'data/edp_api_pro.dart';
import 'data/alarm_service.dart';
import 'data/app_logger.dart';

class DeepLinkHandler extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const DeepLinkHandler({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<DeepLinkHandler> createState() => _DeepLinkHandlerState();
}

class _DeepLinkHandlerState extends State<DeepLinkHandler> {
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Kaltstart-Link: Navigator erst nach dem ersten Frame verfügbar
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleUri(initialUri));
    }

    // Laufende Links
    _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => AppLogger.w('DeepLinkHandler', 'uriLinkStream Fehler', e),
    );
  }

  void _handleUri(Uri uri) async {
    if (uri.scheme != 'truppapp' || uri.host != 'config') return;

    final nav = widget.navigatorKey.currentState;
    final ctx = widget.navigatorKey.currentContext;
    if (nav == null || ctx == null) return;

    final server = uri.queryParameters['server'] ?? '';
    final token = uri.queryParameters['token'] ?? '';
    final issi = uri.queryParameters['issi'] ?? '';
    final hasPbUrl = (uri.queryParameters['pb_url'] ?? '').isNotEmpty;
    final hasProApi = (uri.queryParameters['pro_api_url'] ?? '').isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.qr_code_rounded, color: Colors.red.shade800, size: 22),
            const SizedBox(width: 10),
            const Text('Konfiguration übernehmen?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Folgende Einstellungen werden angewendet:'),
            const SizedBox(height: 12),
            _DialogRow(icon: Icons.dns_rounded, label: 'Server', value: server),
            if (issi.isNotEmpty)
              _DialogRow(icon: Icons.radio_rounded, label: 'ISSI', value: issi),
            if (token.isNotEmpty)
              _DialogRow(
                  icon: Icons.key_rounded,
                  label: 'Token',
                  value: '${token.substring(0, token.length.clamp(0, 6))}…'),
            if (hasPbUrl)
              _DialogRow(
                  icon: Icons.notifications_rounded,
                  label: 'Bereitschafts-App',
                  value: '✓ enthalten'),
            if (hasProApi)
              _DialogRow(
                  icon: Icons.api_rounded,
                  label: 'EDP-Pro-API',
                  value: '✓ enthalten'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Sofort API-Singletons initialisieren damit die App direkt nutzbar ist
    await _applyUriToApis(uri);

    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ConfigScreenWithPrefill(initialDeepLink: uri),
      ),
      (_) => false,
    );
  }

  static Future<void> _applyUriToApis(Uri uri) async {
    final proto = uri.queryParameters['protocol'] ?? 'https';
    final serverPort = uri.queryParameters['server'] ?? '';
    final token = uri.queryParameters['token'] ?? '';
    final issi = uri.queryParameters['issi'] ?? '';
    final trupp = uri.queryParameters['trupp'] ?? '';
    final leiter = uri.queryParameters['leiter'] ?? '';
    final proApiUrl = uri.queryParameters['pro_api_url'] ?? '';
    final pbUrl = uri.queryParameters['pb_url'] ?? '';

    if (serverPort.isEmpty || token.isEmpty) return;

    var host = serverPort;
    var port = proto == 'https' ? 443 : 80;
    if (serverPort.contains(':')) {
      final parts = serverPort.split(':');
      host = parts[0];
      port = int.tryParse(parts[1]) ?? port;
    }

    final cfg = EdpConfig(
      protocol: proto,
      host: host,
      port: port,
      token: token,
      issi: issi,
      trupp: trupp,
      leiter: leiter,
      proApiUrl: proApiUrl,
    );

    await EdpApi.initWithConfig(cfg);

    if (proApiUrl.isNotEmpty) {
      try {
        await EdpApiPro.init(cfg);
      } catch (e) {
        AppLogger.w('DeepLinkHandler', 'EdpApiPro-Init fehlgeschlagen', e);
      }
    }

    if (pbUrl.isNotEmpty) {
      await AlarmService.savePbUrl(pbUrl);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DialogRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DialogRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
