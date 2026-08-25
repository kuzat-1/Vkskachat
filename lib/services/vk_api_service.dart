import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vk_video_downloader/models/video_model.dart';

/// Реальный парсер VK Video.
/// Работает на устройстве пользователя (с телефона VK доступен,
/// в отличие от датацентровых IP).
class VkApiService {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'ru,en;q=0.8',
  };

  // ---------- нормализация ввода ----------

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

  // ---------- получение видео ----------

  /// Пробует несколько способов достать данные о видео.
  /// Возвращает map: title, duration(sec), thumb, qualities{'720': url}
  static Future<Map<String, dynamic>?> resolve(String input) async {
    final id = normalizeVideoId(input);
    if (id == null) return null;

    final bodies = <String>[
      await _get(
          'https://vk.com/al_video.php?act=show&al=1&video=$id'),
      await _get('https://m.vk.com/video$id'),
      await _get('https://vkvideo.ru/video$id'),
    ];

    for (final b in bodies) {
      if (b.isEmpty) continue;
      final parsed = parseVideoPage(b);
      if (parsed != null &&
          (parsed['qualities'] as Map<String, String>).isNotEmpty) {
        return parsed;
      }
    }
    return null;
  }

  static Future<String> _get(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 20));
      return r.body;
    } catch (_) {
      return '';
    }
  }

  /// Достаёт из HTML/JSON страницы ссылки на качества, название и обложку
  static Map<String, dynamic>? parseVideoPage(String body) {
    final files = <String, String>{};
    final re =
        RegExp(r'url(\d{3,4})\\?"\s*:\s*\\?"(https:[^"\\]+)');
    for (final m in re.allMatches(body)) {
      files[m.group(1)!] = _unesc(m.group(2)!);
    }
    if (files.isEmpty) return null;

    var title = '';
    final tm = RegExp(r'"title"\s*:\s*\\?"((?:[^"\\]|\\.)*)')
        .firstMatch(body);
    if (tm != null) title = _unesc(tm.group(1)!);
    if (title.isEmpty || title.toLowerCase().contains('\\u')) {
      final om = RegExp(r'og:title"\s+content="([^"]*)"')
          .firstMatch(body);
      if (om != null) title = _unescHtml(om.group(1)!);
    }

    var dur = 0;
    final dm = RegExp(r'"duration"\s*:\s*(\d+)').firstMatch(body);
    if (dm != null) dur = int.tryParse(dm.group(1)!) ?? 0;

    var thumb = '';
    final hm = RegExp(r'"jpg\d*"\s*:\s*\\?"(https:[^"\\]+)')
        .firstMatch(body);
    if (hm != null) thumb = _unesc(hm.group(1)!);
    if (thumb.isEmpty) {
      final im = RegExp(r'og:image"\s+content="([^"]*)"')
          .firstMatch(body);
      if (im != null) thumb = _unescHtml(im.group(1)!);
    }

    return {
      'title': title.trim().isEmpty ? 'Видео VK' : title.trim(),
      'duration': dur,
      'thumb': thumb,
      'qualities': files,
    };
  }

  /// Раскодирует \" \/ \uXXXX (JSON-эскейпы)
  static String _unesc(String raw) {
    try {
      return jsonDecode('"$raw"') as String;
    } catch (_) {
      return raw.replaceAll(r'\/', '/');
    }
  }

  /// Раскодирует HTML-сущности минимально (&amp; &#44; и т.п.)
  static String _unescHtml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  static String fmtDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  // ---------- поиск по названию ----------

  /// Best-effort поиск: парсим выдачу AJAX-поиска и страницы поиска.
  /// Возвращает список карт {'id': '-123_456'}
  static Future<List<Map<String, String>>> search(String query) async {
    final out = <Map<String, String>>[];
    final q = Uri.encodeQueryComponent(query);

    final urls = <String>[
      'https://vk.com/al_search.php?al=1&c%5Bsection%5D=video&c%5Bq%5D=$q',
      'https://vkvideo.ru/search?q=$q',
    ];

    for (final url in urls) {
      final body = await _get(url);
      if (body.isEmpty) continue;
      final seen = <String>{};
      final re = RegExp(r'video(-?\d+)_(\d+)');
      for (final m in re.allMatches(body)) {
        final vid = '${m.group(1)}_${m.group(2)}';
        if (seen.contains(vid)) continue;
        seen.add(vid);
        out.add({'id': vid});
        if (out.length >= 20) break;
      }
      if (out.isNotEmpty) return out;
    }
    return out;
  }
}
