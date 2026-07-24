// lib/pro/pro_dashboard_screen.dart
import 'package:flutter/material.dart';
import '../data/edp_api.dart';
import '../data/edp_api_pro.dart';
import 'einsatz_navigation_screen.dart';
import 'staerke_edp_screen.dart';
import 'issi_picker_screen.dart';
import 'fahrzeug_karte_screen.dart';

class ProDashboardScreen extends StatefulWidget {
  const ProDashboardScreen({super.key});

  @override
  State<ProDashboardScreen> createState() => _ProDashboardScreenState();
}

class _ProDashboardScreenState extends State<ProDashboardScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _logging = false;
  bool _loggedIn = false;
  String? _loginError;
  String? _loggedInUser;

  @override
  void initState() {
    super.initState();
    _checkExistingToken();
    _loadSavedUser();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingToken() async {
    final api = EdpApiPro.instance;
    if (api != null && api.hasToken) {
      final creds = await EdpApiPro.loadCredentials();
      if (mounted) {
        setState(() {
          _loggedIn = true;
          _loggedInUser = creds?.user;
        });
      }
    }
  }

  Future<void> _loadSavedUser() async {
    final creds = await EdpApiPro.loadCredentials();
    if (creds != null && mounted) {
      _userCtrl.text = creds.user;
    }
  }

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _loginError = 'Benutzername und Passwort erforderlich');
      return;
    }
    setState(() {
      _logging = true;
      _loginError = null;
    });
    try {
      final cfg = EdpApi.instance.config;
      final api = await EdpApiPro.init(cfg);
      final ok = await api.login(user, pass);
      if (!mounted) return;
      if (ok) {
        await EdpApiPro.saveCredentials(user, pass);
        setState(() {
          _loggedIn = true;
          _logging = false;
          _loggedInUser = user;
        });
      } else {
        setState(() {
          _logging = false;
          _loginError = 'Anmeldung fehlgeschlagen. Zugangsdaten prüfen.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _logging = false;
          _loginError = 'Verbindungsfehler: $e';
        });
      }
    }
  }

  Future<void> _logout() async {
    await EdpApiPro.clearTokens();
    if (mounted) {
      setState(() {
        _loggedIn = false;
        _loggedInUser = null;
      });
    }
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pro Funktionen'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildProBadge(),
            const SizedBox(height: 16),
            _loggedIn ? _buildLoggedInCard() : _buildLoginForm(),
            if (_loggedIn) ...
              [
                const SizedBox(height: 20),
                _buildFeatureGrid(),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildProBadge() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade800, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(51),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'PRO',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'EDP-API Integration',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ),
          Icon(Icons.shield, color: Colors.white.withAlpha(204), size: 28),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EDP-API Anmeldung',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Melde dich mit deinen EDP-Zugangsdaten an, um Pro-Funktionen zu nutzen.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _userCtrl,
              decoration: InputDecoration(
                labelText: 'Benutzername',
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'Passwort',
                prefixIcon: const Icon(Icons.lock_outline),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              onSubmitted: (_) => _login(),
            ),
            if (_loginError != null) ...
              [
                const SizedBox(height: 8),
                Text(_loginError!,
                    style: TextStyle(
                        color: Colors.red.shade700, fontSize: 13)),
              ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _logging ? null : _login,
                icon: _logging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.login),
                label: Text(_logging ? 'Anmelden…' : 'Anmelden'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInCard() {
    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.green.shade50,
              child:
                  Icon(Icons.check_circle, color: Colors.green.shade700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Angemeldet',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  if (_loggedInUser != null)
                    Text(_loggedInUser!,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                ],
              ),
            ),
            TextButton(
              onPressed: _logout,
              child: Text('Abmelden',
                  style: TextStyle(color: Colors.red.shade800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verfügbare Funktionen',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _featureTile(
                icon: Icons.local_fire_department,
                title: 'Einsatz\nListe',
                subtitle: 'Aktive Einsätze',
                onTap: () => _open(const EinsatzNavigationScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _featureTile(
                icon: Icons.people,
                title: 'Stärke\nmelden',
                subtitle: 'EDP-Bestand',
                onTap: () => _open(const StaerkeEdpScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _featureTile(
                icon: Icons.radio,
                title: 'ISSI\nauswählen',
                subtitle: 'Vom Server',
                onTap: () async {
                  final result = await Navigator.push<IssiPickerResult>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const IssiPickerScreen()),
                  );
                  if (result != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'ISSI ${result.issi} ausgewählt – in Konfiguration übernehmen'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 4),
                    ));
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _featureTile(
                icon: Icons.map,
                title: 'Fahrzeug\nKarte',
                subtitle: 'GPS-Positionen',
                onTap: () => _open(const FahrzeugKarteScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _featureTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.red.shade800, size: 24),
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.3)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
