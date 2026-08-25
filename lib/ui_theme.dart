import 'package:flutter/material.dart';

/// Дизайн-токены из макета vk-downloader-prototype-2.html
class UiColors {
  static const Color bg = Color(0xFF0A0D12);
  static const Color surface = Color(0xFF12161F);
  static const Color surface2 = Color(0xFF1A2029);
  static const Color border = Color(0xFF232A36);
  static const Color text = Color(0xFFEDEFF3);
  static const Color textDim = Color(0xFF8A93A3);
  static const Color accent = Color(0xFF7C5CFF);
  static const Color accentSoft = Color(0x267C5CFF); // rgba(124,92,255,.15)
  static const Color amber = Color(0xFFFFB020);
  static const Color playCircle = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
  static const Color blue = Color(0xFF4C9EFF);
}

const String kMono = 'monospace';

/// Общие мелкие виджеты дизайна
Widget emptyState(IconData icon, String text) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: UiColors.textDim.withOpacity(.35)),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: UiColors.textDim, fontSize: 13),
        ),
      ],
    ),
  );
}

String filesLabel(int n) {
  if (n % 10 == 1 && n % 100 != 11) return '$n файл';
  if ([2, 3, 4].contains(n % 10) && !(n % 100 >= 12 && n % 100 <= 14)) {
    return '$n файла';
  }
  return '$n файлов';
}
