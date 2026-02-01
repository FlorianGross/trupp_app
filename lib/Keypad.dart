import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

// Status-Konfiguration mit Icons und Texten
class StatusConfig {
  final int number;
  final String title;
  final IconData icon;
  final Color color;
  final bool isAlwaysAvailable;

  const StatusConfig({
    required this.number,
    required this.title,
    required this.icon,
    required this.color,
    this.isAlwaysAvailable = false,
  });
}

// Alle Status-Konfigurationen
const Map<int, StatusConfig> statusConfigs = {
  1: StatusConfig(
    number: 1,
    title: 'Einsatzbereit',
    icon: Icons.radio,
    color: Colors.green,
    isAlwaysAvailable: true,
  ),
  2: StatusConfig(
    number: 2,
    title: 'Wache',
    icon: Icons.home,
    color: Colors.blue,
    isAlwaysAvailable: true,
  ),
  3: StatusConfig(
    number: 3,
    title: 'Auftrag',
    icon: Icons.assignment_turned_in,
    color: Colors.orange,
    isAlwaysAvailable: true,
  ),
  4: StatusConfig(
    number: 4,
    title: 'Ziel erreicht',
    icon: Icons.location_on,
    color: Colors.purple,
    isAlwaysAvailable: false,
  ),
  5: StatusConfig(
    number: 5,
    title: 'Sprechwunsch',
    icon: Icons.record_voice_over,
    color: Colors.teal,
    isAlwaysAvailable: true,
  ),
  6: StatusConfig(
    number: 6,
    title: 'Nicht bereit',
    icon: Icons.block,
    color: Colors.grey,
    isAlwaysAvailable: true,
  ),
  7: StatusConfig(
    number: 7,
    title: 'Transport',
    icon: Icons.local_shipping,
    color: Colors.indigo,
    isAlwaysAvailable: false,
  ),
  8: StatusConfig(
    number: 8,
    title: 'Angekommen',
    icon: Icons.flag,
    color: Colors.pink,
    isAlwaysAvailable: false,
  ),
  9: StatusConfig(
    number: 9,
    title: 'Sonstiges',
    icon: Icons.info,
    color: Colors.amber,
    isAlwaysAvailable: true,
  ),
  0: StatusConfig(
    number: 0,
    title: 'DRINGEND',
    icon: Icons.emergency,
    color: Colors.red,
    isAlwaysAvailable: true,
  ),
};

class Keypad extends StatelessWidget {
  final void Function(int) onPressed;
  final int? selectedStatus;
  final int? lastPersistentStatus;

  const Keypad({
    super.key,
    required this.onPressed,
    required this.selectedStatus,
    this.lastPersistentStatus,
  });

  bool _isStatusAvailable(int statusNumber) {
    final config = statusConfigs[statusNumber];
    if (config == null) return false;
    if (config.isAlwaysAvailable) return true;

    if (statusNumber == 4) return lastPersistentStatus == 3;
    if (statusNumber == 7) return lastPersistentStatus == 4;
    if (statusNumber == 8) return lastPersistentStatus == 7;

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Dynamische Größen basierend auf Screen
    final isSmallScreen = screenHeight < 700;
    final buttonHeight = isSmallScreen ? 65.0 : 70.0;
    final emergencyHeight = isSmallScreen ? 60.0 : 65.0;
    final spacing = isSmallScreen ? 6.0 : 8.0;
    final buttonWidth = (screenWidth - (spacing * 4) - 32) / 3;

    final normalStatuses = [1, 2, 3, 4, 5, 6, 7, 8, 9];

    return Container(
      padding: EdgeInsets.fromLTRB(16, isSmallScreen ? 12 : 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
            // 3x3 Grid für Status 1-9
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              alignment: WrapAlignment.center,
              children: normalStatuses.map((number) {
                return SizedBox(
                  width: buttonWidth,
                  height: buttonHeight,
                  child: _buildStatusButton(
                    context,
                    number,
                    isSmallScreen: isSmallScreen,
                  ),
                );
              }).toList(),
            ),

            SizedBox(height: spacing + 2),

            // Dringend-Button
            SizedBox(
              width: double.infinity,
              height: emergencyHeight,
              child: _buildStatusButton(
                context,
                0,
                isEmergency: true,
                isSmallScreen: isSmallScreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton(
      BuildContext context,
      int number, {
        bool isEmergency = false,
        bool isSmallScreen = false,
      }) {
    final config = statusConfigs[number];
    if (config == null) return const SizedBox.shrink();

    final isSelected = number == selectedStatus;
    final isAvailable = _isStatusAvailable(number);
    final isDisabled = !isAvailable;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isDisabled ? null : () => onPressed(number),
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: isDisabled ? 0.35 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDisabled
                    ? [Colors.grey.shade300, Colors.grey.shade500]
                    : (isSelected
                    ? [Colors.red.shade600, Colors.red.shade800]
                    : [Colors.red.shade700, Colors.red.shade900]),
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: isDisabled
                  ? []
                  : [
                BoxShadow(
                  color: Colors.red.shade700.withOpacity(0.3),
                  blurRadius: isSelected ? 8 : 4,
                  offset: Offset(0, isSelected ? 4 : 2),
                ),
              ],
              border: isSelected
                  ? Border.all(color: Colors.white, width: 2.5)
                  : null,
            ),
            child: isEmergency
                ? _buildEmergencyContent(config, isSmallScreen)
                : _buildNormalContent(config, isDisabled, isSmallScreen),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalContent(StatusConfig config, bool isDisabled, bool isSmallScreen) {
    final fontSize = isSmallScreen ? 10.0 : 11.0;
    final numberSize = isSmallScreen ? 20.0 : 22.0;
    final iconSize = isSmallScreen ? 22.0 : 24.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 4 : 6,
        vertical: isSmallScreen ? 6 : 8,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon + Nummer in einer Zeile
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                config.icon,
                size: iconSize,
                color: Colors.white.withOpacity(isDisabled ? 0.5 : 1.0),
              ),
              const SizedBox(width: 4),
              Text(
                config.number.toString(),
                style: TextStyle(
                  fontSize: numberSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(isDisabled ? 0.5 : 1.0),
                  height: 1.0,
                ),
              ),
            ],
          ),

          SizedBox(height: isSmallScreen ? 2 : 4),

          // Titel
          Text(
            config.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(isDisabled ? 0.5 : 0.95),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContent(StatusConfig config, bool isSmallScreen) {
    final fontSize = isSmallScreen ? 16.0 : 18.0;
    final iconSize = isSmallScreen ? 24.0 : 28.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          config.icon,
          size: iconSize,
          color: Colors.white,
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '0',
                  style: TextStyle(
                    fontSize: fontSize + 2,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  config.title,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}