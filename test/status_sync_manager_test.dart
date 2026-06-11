import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trupp_app/data/status_queue.dart';
import 'package:trupp_app/data/status_sync_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('status_sync_test');
    await databaseFactory.setDatabasesPath(tempDir.path);
    // Keine EDP-Konfiguration → EdpApi.ensureInitialized() liefert null,
    // alle Sends bleiben offline in der Queue.
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await StatusQueue.instance.close();
    await tempDir.delete(recursive: true);
  });

  test('sendOrQueue ohne Konfiguration: false + Status bleibt pending',
      () async {
    final sent = await StatusSyncManager.instance.sendOrQueue(3);
    expect(sent, false);
    expect(await StatusSyncManager.instance.pendingCount(), 1);

    final batch = await StatusQueue.instance.pendingBatch();
    expect(batch.single.status, 3);
  });

  test('mehrere sendOrQueue bewahren die Reihenfolge', () async {
    await StatusSyncManager.instance.sendOrQueue(1);
    await StatusSyncManager.instance.sendOrQueue(4);

    final batch = await StatusQueue.instance.pendingBatch();
    // Inklusive Status 3 aus dem vorherigen Test (gleiche Singleton-DB)
    expect(batch.map((e) => e.status).toList(), [3, 1, 4]);
  });

  test('flushPendingNow ohne Konfiguration: false, nichts geht verloren',
      () async {
    final before = await StatusSyncManager.instance.pendingCount();
    final flushed = await StatusSyncManager.instance.flushPendingNow();
    expect(flushed, false);
    expect(await StatusSyncManager.instance.pendingCount(), before);
  });

  test('parallele sendOrQueue-Aufrufe laufen seriell und verlieren nichts',
      () async {
    final before = await StatusSyncManager.instance.pendingCount();
    await Future.wait([
      StatusSyncManager.instance.sendOrQueue(2),
      StatusSyncManager.instance.sendOrQueue(6),
      StatusSyncManager.instance.sendOrQueue(1),
    ]);
    expect(await StatusSyncManager.instance.pendingCount(), before + 3);
  });
}
