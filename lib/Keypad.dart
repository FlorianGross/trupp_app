import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

const Map<int, String> statusDescriptions = {
  1: "Einsatzbereit Funk",
  2: "Wache",
  3: "Auftrag Angenommen",
  4: "Ziel erreicht",
  5: "Sprechwunsch",
  6: "Nicht Einsatzbereit",
  7: "Transport",
  8: "Ziel Erreicht",
  9: "Sonstiges",
  0: "Dringend",
};

class Keypad extends StatelessWidget {
  final void Function(int) onPressed;
  final int? selectedStatus;

  const Keypad({
    super.key,
    required this.onPressed,
    required this.selectedStatus,
  });

  @override
  Widget build(BuildContext context) {
    final normalButtons = List.generate(9, (i) => i + 1);
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonWidth = (screenWidth - 48) / 3; // 3 buttons with spacing

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: normalButtons.map((number) {
              return SizedBox(
                width: buttonWidth,
                height: 72,
                child: _buildButton(context, number),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: buttonWidth,
            height: 72,
            child: _buildButton(context, 0),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, int number) {
    final isSelected = number == selectedStatus;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onPressed(number),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isSelected
                  ? [Colors.red.shade700, Colors.red.shade900]
                  : [Colors.grey.shade700, Colors.grey.shade900],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: (isSelected ? Colors.red.shade800 : Colors.grey.shade800)
                    .withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                number.toString(),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  statusDescriptions[number] ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.95),
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}