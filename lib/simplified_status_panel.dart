import 'package:flutter/material.dart';
import 'data/unit_type_store.dart';

class _Action {
  final String label;
  final String? sublabel;
  final int status;
  final IconData icon;
  final Color color;
  const _Action({
    required this.label,
    this.sublabel,
    required this.status,
    required this.icon,
    required this.color,
  });
}

const _rettungshundeActions = [
  _Action(
    label: 'Am Fahrzeug',
    sublabel: 'Wache',
    status: 2,
    icon: Icons.home,
    color: Colors.blue,
  ),
  _Action(
    label: 'Auf Suche',
    sublabel: null,
    status: 3,
    icon: Icons.search,
    color: Colors.orange,
  ),
  _Action(
    label: 'Patient gefunden',
    sublabel: null,
    status: 4,
    icon: Icons.location_on,
    color: Color(0xFF7B1FA2), // purple
  ),
];

const _helferActions = [
  _Action(
    label: 'Am Fahrzeug',
    sublabel: 'Wache',
    status: 2,
    icon: Icons.home,
    color: Colors.blue,
  ),
  _Action(
    label: 'Im Einsatz',
    sublabel: null,
    status: 3,
    icon: Icons.directions_run,
    color: Colors.orange,
  ),
  _Action(
    label: 'Aufgabe erledigt',
    sublabel: null,
    status: 4,
    icon: Icons.check_circle,
    color: Color(0xFF2E7D32), // green
  ),
];

class SimplifiedStatusPanel extends StatelessWidget {
  final UnitType unitType;
  final void Function(int) onStatusPressed;
  final Future<void> Function() onSendGps;
  final int? selectedStatus;
  final bool gpsLoading;

  const SimplifiedStatusPanel({
    super.key,
    required this.unitType,
    required this.onStatusPressed,
    required this.onSendGps,
    required this.selectedStatus,
    this.gpsLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRhd = unitType == UnitType.rettungshunde;
    final actions = isRhd ? _rettungshundeActions : _helferActions;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 3 Haupt-Status-Buttons
            _buildMainRow(context, actions),
            const SizedBox(height: 8),
            // Untere Zeile: GPS + Sprechwunsch + DRINGEND
            _buildSecondaryRow(context, isRhd),
          ],
        ),
      ),
    );
  }

  Widget _buildMainRow(BuildContext context, List<_Action> actions) {
    return Row(
      children: actions.asMap().entries.map((entry) {
        final i = entry.key;
        final a = entry.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < actions.length - 1 ? 8 : 0),
            child: _buildActionButton(context, a),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSecondaryRow(BuildContext context, bool isRhd) {
    final sprechwunschLabel = isRhd ? 'Sprechwunsch' : 'Hilfe anfordern';
    final dringendLabel = isRhd ? 'DRINGEND' : 'NOTRUF';

    return Row(
      children: [
        // GPS-Button
        Expanded(
          child: _buildGpsButton(context),
        ),
        const SizedBox(width: 8),
        // Sprechwunsch Normal (S5)
        Expanded(
          child: _buildActionButton(
            context,
            _Action(
              label: sprechwunschLabel,
              status: 5,
              icon: Icons.record_voice_over,
              color: const Color(0xFF00695C), // teal
            ),
          ),
        ),
        const SizedBox(width: 8),
        // DRINGEND (S0)
        Expanded(
          child: _buildActionButton(
            context,
            _Action(
              label: dringendLabel,
              status: 0,
              icon: Icons.emergency,
              color: Colors.red.shade700,
            ),
            isEmergency: true,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    _Action action, {
    bool isEmergency = false,
  }) {
    final isSelected = selectedStatus == action.status;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isEmergency
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.red.shade600, Colors.red.shade800],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              action.color.withOpacity(isDark ? 0.7 : 0.85),
              action.color,
            ],
          );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onStatusPressed(action.status),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            gradient: bg,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: Colors.white, width: 2.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: action.color.withOpacity(0.35),
                blurRadius: isSelected ? 8 : 4,
                offset: Offset(0, isSelected ? 4 : 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, color: Colors.white, size: 22),
              const SizedBox(height: 3),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (action.sublabel != null)
                Text(
                  action.sublabel!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGpsButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: gpsLoading ? null : onSendGps,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green.shade500,
                Colors.green.shade700,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.green.shade600.withOpacity(0.35),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              gpsLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location,
                      color: Colors.white, size: 22),
              const SizedBox(height: 3),
              const Text(
                'Standort',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Übertragen',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
