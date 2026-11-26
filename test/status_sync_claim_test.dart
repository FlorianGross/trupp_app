// Ende-zu-Ende gegen einen lokalen HTTP-Server: Claim zwischen „Isolates"
// (gleiche DB) und ISSI-Abgleich nach Profilwechsel.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trupp_app/data/app_prefs.dart';
import 'package:trupp_app/data/status_queue.dart';
import 'package:trupp_app/data/status_sync_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late HttpServer server;
  final received = <Map<String, String>>[];

  void configure({required String issi}) {
    SharedPreferences.setMockInitialValues({
      AppPrefsKeys.protocol: 'http',
      AppPrefsKeys.server: '127.0.0.1:${server.port}',
      AppPrefsKeys.token: 'tok',
      AppPrefsKeys.issi: issi,
      AppPrefsKeys.hasConfig: true,
    });
  }

  setUpAll(() async {
    // flutter_test beantwortet echte HTTP-Requests sonst pauschal mit 400.
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('status_sync_claim_test');
    await databaseFactory.setDatabasesPath(tempDir.path);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      if (req.uri.pathSegments.last == 'setstatus') {
        received.add(req.uri.queryParameters);
      }
      req.response.statusCode = 200;
      req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    await StatusQueue.instance.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    received.clear();
    final pending = await StatusQueue.instance.pendingBatch(limit: 1000);
    await StatusQueue.instance
        .markSentByIds(pending.map((e) => e.id!).toList(), sentAtMs: 0);
    await StatusQueue.instance.purgeOlderThan(Duration.zero);
  });

  test('online: Status wird gesendet, mit ISSI gestempelt, true', () async {
    configure(issi: '111');
    final ok = await StatusSyncManager.instance.sendOrQueue(3);
    expect(ok, true);
    expect(received, [
      {'issi': '111', 'status': '3'}
    ]);
    expect(await StatusSyncManager.instance.pendingCount(), 0);
  });

  test('hält ein anderes Isolate den ältesten Eintrag, wird nichts gesendet',
      () async {
    configure(issi: '111');
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await StatusQueue.instance
        .insert(QueuedStatus(tsMs: now, status: 3, issi: '111'));
    await StatusQueue.instance.insert(
        QueuedStatus(tsMs: now + 1, status: 4, issi: '111'));
    // „Anderes Isolate" sendet gerade Status 3.
    expect(
        await StatusQueue.instance
            .tryClaim(id, lease: const Duration(minutes: 3)),
        true);

    final emptied = await StatusSyncManager.instance.flushPendingNow();
    expect(emptied, false);
    // Weder 3 doppelt noch 4 vorgezogen (Reihenfolge bleibt).
    expect(received, isEmpty);
    expect(await StatusSyncManager.instance.pendingCount(), 2);

    // Anderes Isolate scheitert und gibt frei → nächster Flush sendet beide.
    await StatusQueue.instance.releaseClaim(id);
    expect(await StatusSyncManager.instance.flushPendingNow(), true);
    expect(received.map((q) => q['status']).toList(), ['3', '4']);
  });

  test('nach Profilwechsel: alter Status wird nicht unter neuer ISSI gesendet',
      () async {
    configure(issi: 'alt');
    final now = DateTime.now().millisecondsSinceEpoch;
    await StatusQueue.instance
        .insert(QueuedStatus(tsMs: now, status: 3, issi: 'alt'));

    configure(issi: 'neu');
    final ok = await StatusSyncManager.instance.sendOrQueue(1);
    expect(ok, true);
    expect(received, [
      {'issi': 'neu', 'status': '1'}
    ]);
    expect(await StatusSyncManager.instance.pendingCount(), 0);
  });
}
