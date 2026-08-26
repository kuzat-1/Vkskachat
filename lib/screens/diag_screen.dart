import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/vk_api_service.dart';
import '../ui_theme.dart';

class DiagScreen extends StatefulWidget {
  const DiagScreen({super.key});

  @override
  State<DiagScreen> createState() => _DiagScreenState();
}

class _DiagScreenState extends State<DiagScreen> {
  final TextEditingController _ctrl = TextEditingController(
      text: 'https://vkvideo.ru/video-181215446_456239293?t=2m8s');
  final List<Map<String, String>> _rows = [];
  bool _running = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add(String name, String status, String detail) {
    setState(() {
      _rows.add({'name': name, 'status': status, 'detail': detail});
    });
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _rows.clear();
    });

    // 1. Распознавание ссылки
    final id = VkApiService.normalizeVideoId(_ctrl.text);
    _add('1. Разбор ссылки', id != null ? 'OK' : 'ОШИБКА',
        id ?? 'не удалось найти video{id}_{id}');
    if (id == null) {
      setState(() => _running = false);
      return;
    }

    // 2. Серверы
    for (var i = 0; i < VkApiService.bases.length; i++) {
      final b = VkApiService.bases[i];
      final host = Uri.parse(b).host;
      try {
        final r = await http
            .get(Uri.parse('$b/health'),
                headers: {'X-App-Key': VkApiService.appKey})
            .timeout(const Duration(seconds: 15));
        _add('2.${i + 1} Сервер $host', r.statusCode == 200 ? 'OK' : 'КОД ${r.statusCode}',
            r.body.length > 60 ? r.body.substring(0, 60) : r.body);
      } catch (e) {
        _add('2.${i + 1} Сервер $host', 'НЕДОСТУПЕН', 'нет связи / таймаут');
      }
    }

    // 3–5. Источники VK прямо с телефона
    final sources = <String, String>{
      '3. vk.com/al_video.php':
          'https://vk.com/al_video.php?act=show&al=1&video=$id',
      '4. m.vk.com': 'https://m.vk.com/video$id',
      '5. vkvideo.ru': 'https://vkvideo.ru/video$id',
    };
    for (final e in sources.entries) {
      final body = await VkApiService.fetchVk(e.value);
      if (body.isEmpty) {
        _add(e.key, 'ПУСТО', 'ответ пустой или сеть заблокировала');
        continue;
      }
      final p = VkApiService.parsePage(body);
      if (p == null) {
        _add(e.key, 'БЕЗ ССЫЛОК',
            'ответ ${body.length} симв., качеств не найдено');
      } else {
        final q = (p['qualities'] as Map<String, String>).keys.toList();
        q.sort();
        _add(e.key, 'OK!',
            '${body.length} симв.; качества: ${q.join(", ")}');
      }
    }

    // 6. Полный resolve
    final res = await VkApiService.resolve(_ctrl.text);
    if (res == null) {
      _add('6. Итог', 'ПРОВАЛ', VkApiService.lastError ?? '');
    } else {
      final keys =
          ((res['qualities'] as Map?)?.keys.toList() ?? <String>[])..sort();
      _add('6. Итог', keys.isEmpty ? 'ТОЛЬКО МЕТА' : 'ПОЛНЫЙ УСПЕХ',
          'качества: ${keys.join(", ")}');
    }

    setState(() => _running = false);
  }

  Color _statusColor(String s) {
    if (s.contains('OK')) return Colors.greenAccent;
    if (s == 'ПОЛНЫЙ УСПЕХ') return Colors.greenAccent;
    if (s.startsWith('ТОЛЬКО')) return UiColors.amber;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.bg,
      appBar: AppBar(
        backgroundColor: UiColors.bg,
        title: const Text('Диагностика',
            style: TextStyle(color: UiColors.text)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ctrl,
                style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 12,
                    color: UiColors.text),
                maxLines: 2,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: UiColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: UiColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: UiColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: UiColors.accent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _run,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Center(
                      child: _running
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Проверить ссылку',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    final c = _statusColor(r['status']!);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: UiColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: UiColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(r['name']!,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: UiColors.text)),
                              ),
                              Text(r['status']!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: c)),
                            ],
                          ),
                          if ((r['detail'] ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(r['detail']!,
                                  style: const TextStyle(
                                      fontFamily: kMono,
                                      fontSize: 11,
                                      color: UiColors.textDim)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Text(
                'Пришли мне скриншот этого экрана — починю точно.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: UiColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// silence unused import warning for dart:math if not used later
// ignore: unused_element
var _unused = min(1, 2);
