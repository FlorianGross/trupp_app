import 'package:flutter/material.dart';

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

  const Keypad({super.key, required this.onPressed, required this.selectedStatus});

  @override
  Widget build(BuildContext context) {
    final normalButtons = List.generate(9, (i) => i + 1); // 1–9

    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: normalButtons.map((number) {
              return SizedBox(
                width: MediaQuery.of(context).size.width / 3 - 20,
                child: _buildButton(context, number),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Status 0 zentriert unten
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: MediaQuery.of(context).size.width / 3 - 20,
                child: _buildButton(context, 0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, int number) {
    final isSelected = number == selectedStatus;

    return ElevatedButton(
      onPressed: () => onPressed(number),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: isSelected
            ? Colors.red.shade800
            : Colors.grey.shade800,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        children: [
          Text(
            number.toString(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            statusDescriptions[number] ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
