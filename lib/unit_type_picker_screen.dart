import 'package:flutter/material.dart';
import 'data/unit_type_store.dart';

class UnitTypePickerScreen extends StatefulWidget {
  /// When true, a back-button is shown (opened from menu).
  final bool allowBack;

  /// Called after save when allowBack is false (first-run).
  /// The caller is responsible for navigation to the main screen.
  final Widget Function()? onComplete;

  const UnitTypePickerScreen({
    super.key,
    this.allowBack = false,
    this.onComplete,
  });

  @override
  State<UnitTypePickerScreen> createState() => _UnitTypePickerScreenState();
}

class _UnitTypePickerScreenState extends State<UnitTypePickerScreen> {
  UnitType? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ut = await UnitTypeStore.load();
    if (mounted) setState(() => _selected = ut);
  }

  Future<void> _confirm() async {
    if (_selected == null) return;
    await UnitTypeStore.save(_selected!);
    if (!mounted) return;
    if (widget.allowBack) {
      Navigator.pop(context, _selected);
    } else if (widget.onComplete != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => widget.onComplete!()),
      );
    } else {
      Navigator.pop(context, _selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einheit auswählen'),
        automaticallyImplyLeading: widget.allowBack,
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Welche Einheit nutzt dieses Gerät gerade?',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Du kannst die Auswahl jederzeit über das Menü ändern.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: UnitType.values
                    .map((ut) => _buildCard(ut, scheme))
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected != null ? _confirm : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Bestätigen',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(UnitType ut, ColorScheme scheme) {
    final isSelected = _selected == ut;
    final icon = _iconFor(ut);
    final color = _colorFor(ut);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() => _selected = ut),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.12) : scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : scheme.outlineVariant,
              width: isSelected ? 2.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ut.label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isSelected ? color : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ut.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: color, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(UnitType ut) {
    switch (ut) {
      case UnitType.erfahren:
        return Icons.dashboard_customize;
      case UnitType.rettungshunde:
        return Icons.pets;
      case UnitType.helfer:
        return Icons.person;
    }
  }

  Color _colorFor(UnitType ut) {
    switch (ut) {
      case UnitType.erfahren:
        return Colors.red.shade700;
      case UnitType.rettungshunde:
        return Colors.orange.shade700;
      case UnitType.helfer:
        return Colors.blue.shade700;
    }
  }
}
