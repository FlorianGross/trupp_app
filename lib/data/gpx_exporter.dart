// lib/data/gpx_exporter.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trupp_app/data/location_queue.dart';

class GpxExporter {
  static Future<String> exportAllFixesToGpx() async {
    final prefs = await SharedPreferences.getInstance();
    final issi   = prefs.getString('issi') ?? 'unknown';
    final trupp  = prefs.getString('trupp') ?? '';
    final leiter = prefs.getString('leiter') ?? '';
    final protocol = prefs.getString('protocol') ?? '';
    final server  = prefs.getString('server') ?? ''; // host:port

    final fixes = await LocationQueue.instance.all();
    final now = DateTime.now().toUtc();

    final metaName = trupp.isNotEmpty ? 'Trupp $trupp ($issi)' : 'ISSI $issi';
    final metaDesc = [
      if (leiter.isNotEmpty) 'Ansprechpartner: $leiter',
      if (server.isNotEmpty && protocol.isNotEmpty) 'Server: $protocol://$server',
      'Punkte: ${fixes.length}',
    ].join(' | ');

    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<gpx version="1.1" creator="Trupp App" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
        'http://www.topografix.com/GPX/1/1/gpx.xsd">');

    buf.writeln('  <metadata>');
    buf.writeln('    <name>${_xml(metaName)}</name>');
    buf.writeln('    <desc>${_xml(metaDesc)}</desc>');
    buf.writeln('    <time>${now.toIso8601String()}</time>');
    buf.writeln('  </metadata>');

    buf.writeln('  <trk>');
    buf.writeln('    <name>${_xml(metaName)}</name>');
    buf.writeln('    <trkseg>');

    for (final f in fixes) {
      final t = DateTime.fromMillisecondsSinceEpoch(f.tsMs, isUtc: true);
      buf.writeln('      <trkpt lat="${f.lat.toStringAsFixed(7)}" lon="${f.lon.toStringAsFixed(7)}">');
      buf.writeln('        <time>${t.toIso8601String()}</time>');
      buf.writeln('        <extensions>');
      if (f.acc != null)   buf.writeln('          <accuracy>${f.acc!.toStringAsFixed(2)}</accuracy>');
      if (f.status != null)buf.writeln('          <status>${f.status}</status>');
      buf.writeln('          <is_sent>${f.isSent ? 1 : 0}</is_sent>');
      if (f.sentAtMs != null) {
        buf.writeln('          <sent_at>${DateTime.fromMillisecondsSinceEpoch(f.sentAtMs!, isUtc: true).toIso8601String()}</sent_at>');
      }
      buf.writeln('        </extensions>');
      buf.writeln('      </trkpt>');
    }

    buf.writeln('    </trkseg>');
    buf.writeln('  </trk>');
    buf.writeln('</gpx>');

    final dir = await getTemporaryDirectory();
    final fileName = 'truppapp_${_safe(issi)}_${_tsFile(now)}.gpx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buf.toString(), flush: true);
    return file.path;
  }

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _safe(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');

  static String _tsFile(DateTime t) {
    final y = t.year.toString().padLeft(4, '0');
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm${ss}Z';
  }
}
