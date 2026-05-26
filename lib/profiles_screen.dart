// lib/profiles_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/edp_api.dart';
import 'data/app_prefs.dart';
import 'data/profile_store.dart';
import 'theme/brand_colors.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<AppProfile> _profiles = [];
  String? _activeName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await ProfileStore.all();
    final active = await ProfileStore.activeName();
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _activeName = active;
        _loading = false;
      });
    }
  }

  Future<void> _activate(AppProfile profile) async {
    await ProfileStore.activate(profile);
    await EdpApi.initFromPrefs();
    // Service neu starten damit neues Profil genutzt wird
    try {
      final svc = FlutterBackgroundService();
      if (await svc.isRunning()) {
        svc.invoke('stopService', {});
        await Future.delayed(const Duration(milliseconds: 800));
      }
      final prefs = await SharedPreferences.getInstance();
      final pbConfigured = (prefs.getString(AppPrefsKeys.pbUrl) ?? '').isNotEmpty &&
          (prefs.getString(AppPrefsKeys.issi) ?? '').isNotEmpty;
      if (pbConfigured && !await svc.isRunning()) {
        await svc.startService();
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _activeName = profile.name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profil "${profile.name}" aktiviert'),
          backgroundColor: Theme.of(context).brand.success,
        ),
      );
    }
  }

  Future<void> _delete(AppProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Profil löschen?'),
        content: Text('"${profile.name}" wird unwiderruflich gelöscht.'),
        actions: [
          TextButton(
            child: const Text('Abbrechen'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Löschen'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProfileStore.delete(profile.name);
    await _load();
  }

  Future<void> _openEditor({AppProfile? existing}) async {
    final result = await Navigator.push<AppProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => _ProfileEditorScreen(profile: existing),
      ),
    );
    if (result != null) {
      await ProfileStore.save(result);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konfigurationsprofile'),
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? _buildEmpty()
              : _buildList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: 'Neues Profil',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add_alt_1, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Noch keine Profile gespeichert',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Tippe auf + um ein Profil anzulegen',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _profiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildCard(_profiles[i]),
    );
  }

  Widget _buildCard(AppProfile profile) {
    final isActive = profile.name == _activeName;
    return Card(
      elevation: isActive ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: Colors.red.shade700, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isActive ? null : () => _activate(profile),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.red.shade800
                      : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isActive ? Colors.white : Colors.grey.shade500,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          profile.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isActive ? Colors.red.shade800 : null,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade800,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'AKTIV',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${profile.protocol}://${profile.server}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'ISSI: ${profile.issi}'
                      '${profile.trupp.isNotEmpty ? '  •  ${profile.trupp}' : ''}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_ProfileAction>(
                onSelected: (action) {
                  if (action == _ProfileAction.edit) _openEditor(existing: profile);
                  if (action == _ProfileAction.delete) _delete(profile);
                  if (action == _ProfileAction.activate) _activate(profile);
                },
                itemBuilder: (_) => [
                  if (!isActive)
                    const PopupMenuItem(
                      value: _ProfileAction.activate,
                      child: ListTile(
                        leading: Icon(Icons.check_circle_outline),
                        title: Text('Aktivieren'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: _ProfileAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Bearbeiten'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: _ProfileAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Löschen', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ProfileAction { activate, edit, delete }

// ─── Profil-Editor ────────────────────────────────────────────────────────────

class _ProfileEditorScreen extends StatefulWidget {
  final AppProfile? profile;
  const _ProfileEditorScreen({this.profile});

  @override
  State<_ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<_ProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _issiCtrl;
  late final TextEditingController _truppCtrl;
  late final TextEditingController _leiterCtrl;
  late final TextEditingController _pbUrlCtrl;
  late String _protocol;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _protocol = p?.protocol ?? 'https';

    // server ist 'host:port'
    String host = '';
    String port = '443';
    if (p != null && p.server.isNotEmpty) {
      final parts = p.server.split(':');
      host = parts[0];
      if (parts.length > 1) port = parts[1];
    }
    _hostCtrl = TextEditingController(text: host);
    _portCtrl = TextEditingController(text: port);
    _tokenCtrl = TextEditingController(text: p?.token ?? '');
    _issiCtrl = TextEditingController(text: p?.issi ?? '');
    _truppCtrl = TextEditingController(text: p?.trupp ?? '');
    _leiterCtrl = TextEditingController(text: p?.leiter ?? '');
    _pbUrlCtrl = TextEditingController(text: p?.pbUrl ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _hostCtrl, _portCtrl, _tokenCtrl,
      _issiCtrl, _truppCtrl, _leiterCtrl, _pbUrlCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final server = '${_hostCtrl.text.trim()}:${_portCtrl.text.trim()}';
    final profile = AppProfile(
      name: _nameCtrl.text.trim(),
      protocol: _protocol,
      server: server,
      token: _tokenCtrl.text.trim(),
      issi: _issiCtrl.text.trim(),
      trupp: _truppCtrl.text.trim(),
      leiter: _leiterCtrl.text.trim(),
      pbUrl: _pbUrlCtrl.text.trim(),
    );
    Navigator.pop(context, profile);
  }

  InputDecoration _dec(String label, {bool required = false}) => InputDecoration(
        labelText: required ? '$label *' : label,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.profile != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Profil bearbeiten' : 'Neues Profil'),
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Speichern', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: _dec('Profilname', required: true),
              validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 20),
            const _SectionHeader('EDP-Server'),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'https', label: Text('HTTPS')),
                ButtonSegment(value: 'http', label: Text('HTTP')),
              ],
              selected: {_protocol},
              onSelectionChanged: (s) => setState(() => _protocol = s.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? Colors.red.shade800
                        : Colors.grey.shade200),
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected) ? Colors.white : Colors.black87),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hostCtrl,
              decoration: _dec('Server (z. B. edp.example.org)', required: true),
              validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portCtrl,
              decoration: _dec('Port', required: true),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tokenCtrl,
              decoration: _dec('Token', required: true),
              validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 20),
            const _SectionHeader('Gerät'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _issiCtrl,
              decoration: _dec('ISSI', required: true),
              validator: (v) => v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _truppCtrl, decoration: _dec('Truppname')),
            const SizedBox(height: 12),
            TextFormField(controller: _leiterCtrl, decoration: _dec('Ansprechpartner')),
            const SizedBox(height: 20),
            const _SectionHeader('Alarmierung (optional)'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pbUrlCtrl,
              decoration: _dec('PocketBase-URL'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(isEdit ? 'Änderungen speichern' : 'Profil erstellen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Colors.red.shade800,
        ),
      );
}
