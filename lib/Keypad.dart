import 'package:flutter/material.dart';

class Keypad extends StatelessWidget {
  final void Function(int) onPressed;

  const Keypad({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final List<int> buttons = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];

    return Column(
      children: [
        // Erste 3 Reihen mit 3 Buttons
        for (int row = 0; row < 3; row++)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (col) {
              int number = buttons[row * 3 + col];
              return _buildKey(number);
            }),
          ),
        SizedBox(height: 10),
        // Letzte Reihe mit nur 0 zentriert
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_buildKey(0)],
        ),
      ],
    );
  }

  Widget _buildKey(int number) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: ElevatedButton(
        onPressed: () => onPressed(number),
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(26),
          backgroundColor: _statusColor(number),
          foregroundColor: Colors.white,
          elevation: 6,
        ),
        child: Text(
          '$number',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Color _statusColor(int number) {
    // Farben für spezielle Stati (1,3,7 = GPS-Modus)
    if ([1, 3, 7].contains(number)) {
      return Colors.red.shade700;
    }
    return Colors.grey.shade800;
  }
}
