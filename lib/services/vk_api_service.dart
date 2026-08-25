import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Тонкий клиент к нашему серверу-прокси.
/// Все токены VK живут на сервере — пользователи ничего не вводят.
class VkApiService {
  static const String base = 'http://185.221.22.180:8899';
  static const String appKey = 'vkskachat2026';

  static String? lastError;

  /// Возвращает id вида "-123_456789" или null
  static String? normalizeVideoId(String input) {
    final s = input.trim();
    final m = RegExp(r'video(-?\d+)_(\d+)').firstMatch(s);
    if (m != null) return '${m.group(1)}_${m.group(2)}';
    final m2 = RegExp(r'^(-?\d+)_(\d+)$').firstMatch(s);
    if (m2 != null) return s;
    return null;
  }

  static bool looksLikeLinkOrId(String s) => normalizeVideoId(s) != null;

  static String fmtDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  /// data: id,title,duration,thumb,qualities{'720':url},can_download
  static Future<Map<String, dynamic>?> resolve(String input) async {
    lastError = null;
    final id = normalizeVideoId(input);
    if (id == null) return null;
    final j =
        await _getJson('/api/resolve?id=${Uri.encodeQueryComponent(id)}');
    if (j == null) return null;
    if (j['error'] != null) {
      lastError = j['error'].toString();
      return null;
    }
    return j['data'] as Map<String, dynamic>;
  }

  /// results: [{id,title,thumb,duration}]
  static Future<List<Map<String, String>>> search(String query) async {
    lastError = null;
    final j =
        await _getJson('/api/search?q=${Uri.encodeQueryComponent(query)}');
    if (j == null) return const [];
    if (j['error'] != null) {
      lastError = j['error'].toString();
      return const [];
    }
    final list = (j['results'] as List?) ?? const [];
    return list
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>?> _getJson(String path) async {
    try {
      final r = await http
          .get(Uri.parse('$base$path'),
              headers: {'X-App-Key': appKey})
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) {
        lastError = 'Сервер: код ${r.statusCode}';
        return null;
      }
      return jsonDecode(r.body);
    } catch (_) {
      lastError = 'Нет связи с сервером. Проверь интернет.';
      return null;
    }
  }
}
