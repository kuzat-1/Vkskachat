import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Гибридная схема:
/// 1) Сервер (поиск по названию + метаданные через VK API)
/// 2) Прямой скрапинг с телефона (сеть юзера не заблокирована VK)
class VkApiService {
  /// Адреса сервера — приложение само выбирает рабочий
  static const List<String> bases = [
    'https://185.221.22.180.sslip.io',
    'http://185.221.22.180',
  ];
  static int _active = -1;
  static const String appKey = 'vkskachat2026';

  static String? lastError;

  /// Юзер-токен VK для прямых запросов video.get с телефона.
  /// VK отдаёт файлы только с IP, с которого токен был выдан,
  /// поэтому токен живёт на сервере, а использует его приложение (с IP телефона).
  static String? userToken;

  static Future<String?> fetchUserToken() async {
    if (userToken != null && userToken!.isNotEmpty) return userToken;
    final j = await _getJson('/api/get_token');
    final t = (j?['token'] as String?) ?? '';
    userToken = t.isEmpty ? null : t;
    return userToken;
  }

  static const Map<String, String> _vkHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'ru,en;q=0.8',
  };

  // ---------- нормализация ----------

  static String? normalizeVideoId(String input) {
    final s = input.trim();
    final m = RegExp(r'video(-?\d+)_(\d+)').firstMatch(s);
    if (m != null) return '${m.group(1)}_${m.group(2)}';
    // Новый формат vkvideo: video230329053456240782 (без подчёркивания)
    final slug = RegExp(r'video(\d{10,})').firstMatch(s);
    if (slug != null) return 'slug:${slug.group(1)}';
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

  /// Возвращает map: id,title,duration,thumb,qualities{'720':url},source
  static Future<Map<String, dynamic>?> resolve(String input) async {
    lastError = null;
    final id = normalizeVideoId(input);
    if (id == null) return null;

    // 1) Сервер: метаданные (+файлы, когда на сервере появится юзер-токен)
    Map<String, dynamic>? serverData;
    final j =
        await _getJson('/api/resolve?id=${Uri.encodeQueryComponent(id)}');
    if (j != null && j['error'] == null && j['data'] != null) {
      serverData = j['data'] as Map<String, dynamic>;
      if (((serverData['qualities'] as Map?)?.isNotEmpty ?? false)) {
        return serverData;
      }
    }

    // 2) Прямой video.get с телефона через юзер-токен с сервера.
    //    Сервер в США не получает files (VK привязывает файлы к IP выдачи
    //    токена), а телефон юзера — тот самый IP → файлы приходят.
    final direct = await resolveDirect(id, serverData);
    if (direct != null) return direct;

    // 3) Прямой скрапинг с устройства
    final local = await resolveLocal(id);
    if (local != null) {
      if (serverData != null) {
        local['title'] ??= serverData['title'];
        local['thumb'] ??= serverData['thumb'];
        if ((local['duration'] as int? ?? 0) == 0) {
          local['duration'] = serverData['duration'];
        }
      }
      return local;
    }

    if (serverData != null) return serverData; // метаданные без файлов

    lastError = lastError ?? 'Не удалось получить видео';
    return null;
  }

  /// video.get напрямую с телефона (токен с сервера).
  static Future<Map<String, dynamic>?> resolveDirect(
      String id, Map<String, dynamic>? meta) async {
    final tok = await fetchUserToken();
    if (tok == null || tok.isEmpty) return null;
    final raw = id.startsWith('slug:') ? id.substring(5) : id;
    final url = Uri.parse('https://api.vk.com/method/video.get').replace(
      queryParameters: {
        'videos': raw,
        'access_token': tok,
        'v': '5.199',
      },
    );
    try {
      final r = await http
          .get(url, headers: {'User-Agent': 'VKAndroidApp/8.42'})
          .timeout(const Duration(seconds: 20));
      final Map<String, dynamic> j = jsonDecode(r.body);
      if (j['error'] != null) return null;
      final items = (j['response']?['items'] as List?) ?? const [];
      if (items.isEmpty) return null;
      final it = items.first as Map<String, dynamic>;
      final files = <String, String>{};
      final src = (it['files'] as Map?) ?? const {};
      for (final e in src.entries) {
        final m = RegExp(r'mp4_(\d+)').firstMatch(e.key.toString());
        if (m != null && e.value != null && e.value.toString().isNotEmpty) {
          files[m.group(1)!] = e.value.toString();
        }
      }
      if (files.isEmpty) return null;

      String thumb = '';
      String? bestPhoto;
      for (final e in it.entries) {
        if (e.key.startsWith('photo_') && e.value is String) {
          final n = int.tryParse(e.key.split('_').last) ?? 0;
          if (n > (int.tryParse(bestPhoto ?? '0') ?? 0)) bestPhoto = e.value as String;
        }
      }
      if (bestPhoto != null) thumb = bestPhoto;
      if (thumb.isEmpty) {
        final ff = it['first_frame'];
        if (ff is List && ff.isNotEmpty && ff.first is Map) {
          final u = (ff.first as Map)['url'];
          if (u is String && u.startsWith('http')) thumb = u;
        }
      }

      return {
        'id': id,
        'title': (it['title'] as String?) ?? (meta?['title'] ?? 'Видео VK'),
        'duration': int.tryParse((it['duration'] ?? 0).toString()) ?? 0,
        'thumb': thumb.isNotEmpty ? thumb : (meta?['thumb'] ?? ''),
        'qualities': files,
        'can_download': true,
        'source': 'direct',
      };
    } catch (_) {
      return null;
    }
  }

  /// Скрапинг с телефона: источники по очереди
  static Future<Map<String, dynamic>?> resolveLocal(String id) async {
    final raw = id.startsWith('slug:') ? id.substring(5) : id;
    final urls = <String>[
      'https://vk.com/al_video.php?act=show&al=1&video=$raw',
      'https://m.vk.com/video$raw',
      'https://vkvideo.ru/video$raw',
    ];
    if (!raw.startsWith('-')) {
      final p = raw.split('_');
      if (p.length == 2) {
        urls.add(
            'https://vk.com/video_ext.php?oid=${p[0]}&id=${p[1]}');
      }
    }
    final bodies = <String>[
      for (final u in urls) await fetchVk(u),
    ];
    for (final b in bodies) {
      if (b.isEmpty) continue;
      final parsed = parsePage(b);
      if (parsed != null &&
          (parsed['qualities'] as Map<String, String>).isNotEmpty) {
        final canon = (parsed['id'] as String?) ?? '';
        parsed['id'] =
            canon.isNotEmpty ? canon : (id.startsWith('slug:') ? id : id);
        parsed['can_download'] = true;
        parsed['source'] = 'local';
        return parsed;
      }
    }
    return null;
  }

  static Future<String> fetchVk(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url), headers: _vkHeaders)
          .timeout(const Duration(seconds: 20));
      return r.body;
    } catch (_) {
      return '';
    }
  }

  /// Достаёт из HTML ссылки качества/название/обложку
  static Map<String, dynamic>? parsePage(String body) {
    final files = <String, String>{};
    final re =
        RegExp(r'url(\d{3,4})\\?"\s*:\s*\\?"(https:[^"\\]+)');
    for (final m in re.allMatches(body)) {
      files[m.group(1)!] = unesc(m.group(2)!);
    }
    if (files.isEmpty) return null;

    var title = '';
    final tm = RegExp(r'"title"\s*:\s*\\?"((?:[^"\\]|\\.)*)')
        .firstMatch(body);
    if (tm != null) title = unesc(tm.group(1)!);

    var dur = 0;
    final dm = RegExp(r'"duration"\s*:\s*(\d+)').firstMatch(body);
    if (dm != null) dur = int.tryParse(dm.group(1)!) ?? 0;

    var thumb = '';
    final hm = RegExp(r'"jpg\d*"\s*:\s*\\?"(https:[^"\\]+)')
        .firstMatch(body);
    if (hm != null) thumb = unesc(hm.group(1)!);

    // канонический id вида -123_456 (для новых ссылок vkvideo)
    var canonId = '';
    final cm = RegExp(r'video(-?\d+)_(\d+)').firstMatch(body);
    if (cm != null) canonId = '${cm.group(1)}_${cm.group(2)}';

    // --- расширенный скан: любые прямые .mp4 ---
    final mp4re = RegExp(
        r'https:(?:\\?/){1,2}[^"\\\s]{10,400}?\.mp4[^"\\\s]{0,80}');
    for (final m in mp4re.allMatches(body)) {
      final u = unesc(m.group(0)!);
      if (!u.startsWith('http')) continue;
      final qm =
          RegExp(r'[_\.\-=/](\d{3,4})\.mp4').firstMatch(u.toLowerCase());
      final key = qm != null ? qm.group(1)! : 'src${files.length}';
      files.putIfAbsent(key, () => u);
    }

    return {
      'id': canonId,
      'title': title.trim().isEmpty ? 'Видео VK' : title.trim(),
      'duration': dur,
      'thumb': thumb,
      'qualities': files,
    };
  }

  static String unesc(String raw) {
    try {
      return jsonDecode('"$raw"') as String;
    } catch (_) {
      return raw.replaceAll(r'\/', '/');
    }
  }

  // ---------- ПОИСК (через сервер) ----------

  /// results: [{id,title,thumb,duration(int),views}]
  static Future<List<Map<String, dynamic>>> search(String query) async {
    lastError = null;
    final j =
        await _getJson('/api/search?q=${Uri.encodeQueryComponent(query)}');
    if (j == null) return const [];
    if (j['error'] != null) {
      lastError = j['error'].toString();
      return const [];
    }
    final list = (j['results'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ---------- РЕКОМЕНДАЦИИ (лента через сервер) ----------

  static Future<List<Map<String, dynamic>>> recommendations(
      {String? cat, int limit = 12}) async {
    lastError = null;
    var path = '/api/recommendations?limit=$limit';
    if (cat != null && cat.isNotEmpty) {
      path += '&cat=${Uri.encodeQueryComponent(cat)}';
    }
    final j = await _getJson(path);
    if (j == null) return const [];
    if (j['error'] != null) {
      lastError = j['error'].toString();
      return const [];
    }
    final list = (j['results'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ---------- транспорт к серверу ----------

  static Future<Map<String, dynamic>?> _getJson(String path) async {
    lastError = null;
    final order = <int>[];
    if (_active >= 0) order.add(_active);
    for (var i = 0; i < bases.length; i++) {
      if (!order.contains(i)) order.add(i);
    }
    Object? caught;
    for (final i in order) {
      try {
        final r = await http
            .get(Uri.parse('${bases[i]}$path'),
                headers: {'X-App-Key': appKey})
            .timeout(const Duration(seconds: 20));
        _active = i;
        if (r.statusCode != 200) {
          lastError = 'Сервер: код ${r.statusCode}';
          return null;
        }
        return jsonDecode(r.body);
      } catch (e) {
        caught = e;
      }
    }
    if (caught != null) lastError = 'Нет связи с сервером';
    return null;
  }
}
