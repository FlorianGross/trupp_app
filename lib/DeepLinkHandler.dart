import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'ConfigScreen.dart';

class DeepLinkHandler extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey; // ◀ NavigatorKey annehmen

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

    // Kaltstart-Link
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _handleUri(initialUri);
    }

    // Laufende Links
    _appLinks.uriLinkStream.listen(_handleUri);
  }

  void _handleUri(Uri uri) async {
    if (uri.scheme == 'truppapp' && uri.host == 'config') {
      final nav = widget.navigatorKey.currentState;
      final ctx = widget.navigatorKey.currentContext;
      if (nav == null || ctx == null) return;

      final confirmed = await showPlatformDialog<bool>(
        context: ctx,
        builder: (_) => PlatformAlertDialog(
          title: const Text('Konfiguration übernehmen?'),
          content: const Text('Möchtest du die Konfiguration anwenden?'),
          actions: [
            PlatformDialogAction(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Nein'),
            ),
            PlatformDialogAction(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ja'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        nav.pushAndRemoveUntil(
          platformPageRoute(
            context: ctx,
            builder: (_) => ConfigScreenWithPrefill(initialDeepLink: uri),
          ),
              (_) => false,
        );

      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
