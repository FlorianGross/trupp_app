import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trupp_app/data/status_queue.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('status_queue_test');
    await databaseFactory.setDatabasesPath(tempDir.path);
  });

  tearDownAll(() async {
    await StatusQueue.instance.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    // Tabelle zwischen Tests leeren
    final pending = await StatusQueue.instance.pendingBatch(limit: 1000);
    await StatusQueue.instance.markSentByIds(
      pending.map((e) => e.id!).toList(),
      sentAtMs: 0,
    );
    await StatusQueue.instance.purgeOlderThan(Duration.zero);
  });

  test('insert erhöht pendingCount', () async {
    expect(await StatusQueue.instance.pendingCount(), 0);
    await StatusQueue.instance.insert(QueuedStatus(
      tsMs: DateTime.now().millisecondsSinceEpoch,
      status: 3,
    ));
    expect(await StatusQueue.instance.pendingCount(), 1);
  });

  test('pendingBatch liefert FIFO-Reihenfolge (älteste zuerst)', () async {
    final base = DateTime.now().millisecondsSinceEpoch;
    await StatusQueue.instance.insert(QueuedStatus(tsMs: base + 200, status: 7));
    await StatusQueue.instance.insert(QueuedStatus(tsMs: base, status: 1));
    await StatusQueue.instance.insert(QueuedStatus(tsMs: base + 100, status: 3));

    final batch = await StatusQueue.instance.pendingBatch();
    expect(batch.map((e) => e.status).toList(), [1, 3, 7]);
  });

  test('markSentByIds entfernt aus pending', () async {
    final base = DateTime.now().millisecondsSinceEpoch;
    await StatusQueue.instance.insert(QueuedStatus(tsMs: base, status: 1));
    await StatusQueue.instance.insert(QueuedStatus(tsMs: base + 1, status: 2));

    final batch = await StatusQueue.instance.pendingBatch();
    await StatusQueue.instance
        .markSentByIds([batch.first.id!], sentAtMs: base + 2);

    final remaining = await StatusQueue.instance.pendingBatch();
    expect(remaining.length, 1);
    expect(remaining.first.status, 2);
  });

  test('discardPendingOlderThan verwirft nur veraltete pending Einträge',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final oldTs = now - const Duration(hours: 7).inMilliseconds;
    await StatusQueue.instance.insert(QueuedStatus(tsMs: oldTs, status: 3));
    await StatusQueue.instance.insert(QueuedStatus(tsMs: now, status: 1));

    final discarded = await StatusQueue.instance
        .discardPendingOlderThan(const Duration(hours: 6));
    expect(discarded, 1);

    final remaining = await StatusQueue.instance.pendingBatch();
    expect(remaining.length, 1);
    expect(remaining.first.status, 1);
  });

  test('markSdsNotified setzt das SDS-Flag, ohne den Status zu senden',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await StatusQueue.instance.insert(QueuedStatus(tsMs: now, status: 3));

    var batch = await StatusQueue.instance.pendingBatch();
    expect(batch.single.sdsNotified, false);

    await StatusQueue.instance.markSdsNotified(batch.single.id!);

    batch = await StatusQueue.instance.pendingBatch();
    // Eintrag bleibt pending (nur die SDS-Nachmeldung ist markiert).
    expect(batch.single.sdsNotified, true);
    expect(batch.single.isSent, false);
  });

  test('purgeOlderThan löscht nur gesendete Einträge', () async {
    final old = DateTime.now().millisecondsSinceEpoch -
        const Duration(days: 8).inMilliseconds;
    await StatusQueue.instance.insert(QueuedStatus(tsMs: old, status: 5));
    final batch = await StatusQueue.instance.pendingBatch();

    // Ungesendet → purge greift nicht
    expect(
        await StatusQueue.instance.purgeOlderThan(const Duration(days: 7)), 0);

    await StatusQueue.instance.markSentByIds([batch.first.id!], sentAtMs: old);
    expect(
        await StatusQueue.instance.purgeOlderThan(const Duration(days: 7)), 1);
  });
}
