import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vk_video_downloader/models/video_model.dart';

/// VK Video: официальный API (с токеном) + скраперы как запасной путь.
class VkApiService {
  /// Персональный токен пользователя (вводится в настройках приложения)
  static String? token;

  /// Последняя ошибка API для показа пользователю
  static String? lastError;

  static const _api = 'https://api.vk.com/method';
  static const _v = '5.199';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'ru,en;q=0.8',
  };

  static bool get hasToken => token != null && token!.trim().isNotEmpty;

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

  static String fmtDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  // ---------- РЕЗОЛВ ВИДЕО ----------

  /// Пробует официальный API (если есть токен), потом скраперы.
  /// Возвращает map: title, duration(sec), thumb, qualities{'720': url}
  static Future<Map<String, dynamic>?> resolve(String input) async {
    lastError = null;
    final id = normalizeVideoId(input);
    if (id == null) return null;

    if (hasToken) {
      final viaApi = await resolveByApi(id);
      if (viaApi != null) return viaApi;
    }

    // Скрапер-fallback
    final bodies = <String>[
      await _get('https://vk.com/al_video.php?act=show&al=1&video=$id'),
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

  /// Официальный метод video.get
  static Future<Map<String, dynamic>?> resolveByApi(String id) async {
    try {
      final uri =
          '$_api/video.get?v=$_v&videos=$id&access_token=${Uri.encodeQueryComponent(token!)}';
      final r =
          await http.get(Uri.parse(uri)).timeout(const Duration(seconds: 20));
      final j = jsonDecode(r.body);
      if (j['error'] != null) {
        lastError = 'VK API: ${j['error']['error_msg']}';
        return null;
      }
      final items = j['response']['items'] as List;
      if (items.isEmpty) {
        lastError = 'Видео не найдено';
        return null;
      }
      final it = items[0] as Map;
      final files = <String, String>{};
      final f = it['files'];
      if (f is Map) {
        f.forEach((k, vv) {
          final m = RegExp(r'mp4_(\d+)').firstMatch(k.toString());
          if (m != null && vv is String && vv.isNotEmpty) {
            files[m.group(1)!] = vv;
          }
        });
      }
      if (files.isEmpty) {
        lastError =
            'VK не отдал файлы для этого видео (возможно, оно закрытое)';
        return null;
      }
      return {
        'title': (it['title'] ?? 'Видео VK').toString(),
        'duration': (it['duration'] ?? 0) as int,
        'thumb': bestPhoto(it),
        'qualities': files,
      };
    } catch (_) {
      lastError = 'Нет соединения с VK API';
      return null;
    }
  }

  static String bestPhoto(Map it) {
    var best = '';
    var bs = -1;
    it.forEach((k, vv) {
      if (k.toString().startsWith('photo_') && vv is String) {
        final n = int.tryParse(k.toString().substring(6));
        if (n != null && n > bs) {
          bs = n;
          best = vv;
        }
      }
    });
    return best;
  }

  // ---------- ПОИСК ----------

  /// Поиск: сначала официальный video.search (если есть токен),
  /// затем скрапер выдачи.
  /// Возвращает список карт: id, title, thumb, duration
  static Future<List<Map<String, String>>> search(String query) async {
    lastError = null;
    if (hasToken) {
      final rs = await searchByApi(query);
      if (rs.isNotEmpty) return rs;
      if (lastError == null || lastError!.isEmpty) return rs;
    }
    return searchByScrape(query);
  }

  static Future<List<Map<String, String>>> searchByApi(
      String query) async {
    try {
      final uri = '$_api/video.search?v=$_v'
          '&q=${Uri.encodeQueryComponent(query)}'
          '&sort=2&count=20'
          '&access_token=${Uri.encodeQueryComponent(token!)}';
      final r =
          await http.get(Uri.parse(uri)).timeout(const Duration(seconds: 20));
      final j = jsonDecode(r.body);
      if (j['error'] != null) {
        lastError = 'VK API: ${j['error']['error_msg']}';
        return [];
      }
      final items = j['response']['items'] as List;
      return [
        for (final it in items.cast<Map>())
          {
            'id': '${it['owner_id']}_${it['id']}',
            'title': (it['title'] ?? '').toString(),
            'thumb': bestPhoto(it),
            'duration': ((it['duration'] ?? 0) as int).toString(),
          }
      ];
    } catch (_) {
      lastError = 'Нет соединения с VK API';
      return [];
    }
  }

  static Future<List<Map<String, String>>> searchByScrape(
      String query) async {
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
        out.add({'id': vid, 'title': '', 'thumb': '', 'duration': ''});
        if (out.length >= 20) break;
      }
      if (out.isNotEmpty) return out;
    }
    return out;
  }

  // ---------- вспомогательное ----------

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

  /// Достаёт из HTML ссылки на качества, название и обложку
  static Map<String, dynamic>? parseVideoPage(String body) {
    final files = <String, String>{};
    final re = RegExp(r'url(\d{3,4})\\?"\s*:\s*\\?"(https:[^"\\]+)');
    for (final m in re.allMatches(body)) {
      files[m.group(1)!] = _unesc(m.group(2)!);
    }
    if (files.isEmpty) return null;

    var title = '';
    final tm = RegExp(r'"title"\s*:\s*\\?"((?:[^"\\]|\\.)*)')
        .firstMatch(body);
    if (tm != null) title = _unesc(tm.group(1)!);

    var dur = 0;
    final dm = RegExp(r'"duration"\s*:\s*(\d+)').firstMatch(body);
    if (dm != null) dur = int.tryParse(dm.group(1)!) ?? 0;

    var thumb = '';
    final hm = RegExp(r'"jpg\d*"\s*:\s*\\?"(https:[^"\\]+)')
        .firstMatch(body);
    if (hm != null) thumb = _unesc(hm.group(1)!);

    return {
      'title': title.trim().isEmpty ? 'Видео VK' : title.trim(),
      'duration': dur,
      'thumb': thumb,
      'qualities': files,
    };
  }

  static String _unesc(String raw) {
    try {
      return jsonDecode('"$raw"') as String;
    } catch (_) {
      return raw.replaceAll(r'\/', '/');
    }
  }
}
