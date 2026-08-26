import 'package:flutter/material.dart';
import '../models/video_model.dart';
import '../services/download_service.dart';
import '../services/vk_api_service.dart';
import '../state/app_state.dart';
import '../ui_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onGoToDownloads});

  final VoidCallback onGoToDownloads;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final TextEditingController _input = TextEditingController();
  final DownloadService _downloader = DownloadService();

  bool _loading = false;
  String? _error;
  VideoModel? _preview;
  Map<String, String> _qualities = {};
  String _selected = '';
  List<Map<String, String>> _results = const [];

  @override
  void dispose() {
    _tabs.dispose();
    _input.dispose();
    super.dispose();
  }

  // ---------- логика ----------

  Future<void> _go() async {
    final String raw = _input.text.trim();
    if (raw.isEmpty || _loading) return;

    appState.addHistory(raw);

    if (VkApiService.looksLikeLinkOrId(raw)) {
      await _resolve(raw);
    } else {
      await _doSearch(raw);
    }
  }

  Future<void> _resolve(String raw) async {
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
      _results = const [];
    });
    try {
      final res = await VkApiService.resolve(raw);
      if (!mounted) return;
      if (res == null) throw Exception(VkApiService.lastError ?? '');

      final qualities =
          Map<String, String>.from(res['qualities'] as Map);
      final v = VideoModel(
        id: (res['id'] as String?) ??
            (VkApiService.normalizeVideoId(raw) ?? raw),
        title: res['title'] as String,
        thumbnailUrl: res['thumb'] as String,
        videoUrl: '',
        channelName: 'VK Видео',
        views: 0,
        duration: VkApiService.fmtDuration(
            (res['duration'] as int?) ?? 0),
        qualities: [],
      );

      setState(() {
        _preview = v;
        _qualities = qualities;
        _selected = _pickDefault(qualities.keys.toList());
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        final err = VkApiService.lastError;
        _error = 'Не получилось открыть видео.'
            '${err != null && err.isNotEmpty ? '\n$err' : ''}';
      });
    }
  }

  String _pickDefault(List<String> keys) {
    if (keys.contains('720')) return '720';
    final nums = keys.map((e) => int.tryParse(e) ?? 0).toList()..sort();
    final lower = nums.where((n) => n <= 720 && n > 0).toList();
    return (lower.isNotEmpty ? lower.last : nums.first).toString();
  }

  Future<void> _doSearch(String query) async {
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
      _results = const [];
    });
    try {
      final rs = await VkApiService.search(query);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = rs;
        if (rs.isEmpty) {
          final err = VkApiService.lastError;
          _error = (err != null && err.isNotEmpty)
              ? 'Поиск не дал результатов.\n$err'
              : 'Ничего не найдено. Попробуйте другой запрос.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Поиск временно не работает. Попробуйте ссылку.';
      });
    }
  }

  int _durSec(String s) {
    final parts =
        s.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    if (parts.length == 2) return parts[0] * 60 + parts[1];
    if (parts.length == 1) return parts[0];
    return 0;
  }

  String _sizeFor(String q) {
    if (_preview == null) return '';
    const rates = {
      '240': 0.35,
      '360': 0.6,
      '480': 0.95,
      '720': 1.6,
      '1080': 2.6,
      '1440': 4.5,
      '2160': 8.0,
    };
    final sec = _durSec(_preview!.duration);
    if (sec <= 0) return '';
    final mb = ((rates[q] ?? 1.0) * sec).round();
    return '~$mb МБ';
  }

  Future<void> _startDownload() async {
    final v = _preview;
    if (v == null || _selected.isEmpty) return;
    final url = _qualities[_selected];
    if (url == null || url.isEmpty) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final item = DownloadItem(
      id: id,
      title: v.title.isEmpty ? 'Видео' : v.title,
      quality: '${_selected}p',
      sizeLabel: _sizeFor(_selected),
      filePath: '',
    );
    appState.addDownload(item);
    widget.onGoToDownloads();

    int lastPercent = -1;
    try {
      final path = await _downloader.downloadVideo(
          v, _selected, url, (received, total) {
        if (total <= 0) return;
        final pct = (received / total * 100).floor();
        if (pct != lastPercent) {
          lastPercent = pct;
          appState.updateProgress(id, received / total);
        }
      });
      item.filePath = path ?? '';
      appState.markDone(id);
    } catch (_) {
      appState.remove(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: UiColors.surface2,
            content: Text('Ошибка скачивания',
                style: TextStyle(color: UiColors.text)),
          ),
        );
      }
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              labelColor: UiColors.text,
              unselectedLabelColor: UiColors.textDim,
              labelStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: const UnderlineTabIndicator(
                borderSide:
                    BorderSide(width: 3, color: UiColors.accent),
              ),
              tabs: const [
                Tab(text: 'Поиск'),
                Tab(text: 'История'),
                Tab(text: 'Избранное'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _searchTab(),
                  _historyTab(),
                  emptyState(Icons.favorite_border,
                      'Здесь появятся видео, добавленные в избранное'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 26),
          _hero(),
          const SizedBox(height: 22),
          _searchBox(),
          const SizedBox(height: 22),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: CircularProgressIndicator(color: UiColors.accent),
              ),
            )
          else ...[
            if (_preview != null)
              _previewSection()
            else if (_results.isNotEmpty)
              _resultsSection()
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: UiColors.textDim,
                      fontSize: 13,
                      height: 1.5),
                ),
              )
            else
              _hintBlock(),
          ],
        ],
      ),
    );
  }

  Widget _hero() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [UiColors.accent, UiColors.blue],
            ),
          ),
          child: const Icon(Icons.arrow_downward_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(height: 14),
        const Text(
          'Видеозагрузчик',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
            color: UiColors.accent,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ссылка на видео или название для поиска',
          style: TextStyle(fontSize: 13, color: UiColors.textDim),
        ),
        const SizedBox(height: 4),
        const Text(
          'сборка 12 · гибрид',
          style: TextStyle(
              fontFamily: kMono,
              fontSize: 10,
              color: UiColors.textDim),
        ),
      ],
    );
  }

  Widget _searchBox() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: UiColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.download_outlined,
              color: UiColors.textDim, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _input,
              style:
                  const TextStyle(color: UiColors.text, fontSize: 15),
              decoration: const InputDecoration.collapsed(
                hintText: 'Ссылка на видео или название',
                hintStyle:
                    TextStyle(color: UiColors.textDim, fontSize: 15),
              ),
              onSubmitted: (_) => _go(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _go,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: UiColors.accent, shape: BoxShape.circle),
              child: const Icon(Icons.search,
                  color: Colors.white, size: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintBlock() {
    return Padding(
      padding: const EdgeInsets.only(left: 40, right: 40, top: 40),
      child: Column(
        children: [
          Icon(Icons.desktop_windows_outlined,
              size: 40, color: UiColors.textDim.withOpacity(.4)),
          const SizedBox(height: 14),
          const Text(
            'Вставьте ссылку вида vk.com/video…\nили введите название видео',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: UiColors.textDim, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _resultsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Найдено видео',
            style: TextStyle(
                fontSize: 12,
                color: UiColors.textDim,
                letterSpacing: 0.7),
          ),
          const SizedBox(height: 10),
          ..._results.map((r) => _resultRow(r)),
        ],
      ),
    );
  }

  Widget _resultRow(Map<String, String> r) {
    final vid = r['id'] ?? '';
    final title = (r['title'] ?? '').trim();
    final thumb = r['thumb'] ?? '';
    final durSec = int.tryParse(r['duration'] ?? '') ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        _input.text = 'https://vk.com/video$vid';
        _resolve(_input.text);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: UiColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: UiColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 100,
                height: 62,
                child: thumb.isNotEmpty
                    ? Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _thumbPlaceholder(),
                      )
                    : _thumbPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? 'Видео $vid' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: UiColors.text),
                  ),
                  if (durSec > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      VkApiService.fmtDuration(durSec),
                      style: const TextStyle(
                          fontFamily: kMono,
                          fontSize: 11,
                          color: UiColors.textDim),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewSection() {
    final v = _preview!;
    final bool noLinks = _qualities.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: UiColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: UiColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (v.thumbnailUrl.isNotEmpty)
                        Image.network(
                          v.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _thumbPlaceholder(),
                        )
                      else
                        _thumbPlaceholder(),
                      Center(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            color: UiColors.playCircle,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow,
                              color: Colors.white),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x99000000),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            v.duration,
                            style: const TextStyle(
                                fontFamily: kMono,
                                fontSize: 11,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: UiColors.text),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'VK Видео',
                        style: TextStyle(
                            fontSize: 13, color: UiColors.textDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (noLinks)
            Container(
              margin: const EdgeInsets.only(top: 18),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: UiColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: UiColors.accent),
              ),
              child: const Text(
                'Это видео нашлось, но ссылки на файл для него '
                'пока не выданы. Мы подключаем полный доступ — '
                'попробуй позже или другое видео.',
                style: TextStyle(
                    fontSize: 13, height: 1.45, color: UiColors.text),
              ),
            )
          else ...[
            const SizedBox(height: 18),
            const Text(
              'Качество для скачивания',
              style: TextStyle(
                  fontSize: 12,
                  color: UiColors.textDim,
                  letterSpacing: 0.7),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _qualities.keys.map((q) => _chip(q)).toList(),
            ),
            const SizedBox(height: 20),
            _downloadButton(),
          ],
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [UiColors.surface2, UiColors.border],
        ),
      ),
    );
  }

  Widget _chip(String q) {
    final bool sel = q == _selected;
    final String size = _sizeFor(q);
    return GestureDetector(
      onTap: () => setState(() => _selected = q),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? UiColors.accentSoft : UiColors.surface,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: sel ? UiColors.accent : UiColors.border),
        ),
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: kMono,
              fontSize: 13,
              color: sel ? UiColors.text : UiColors.textDim,
            ),
            children: [
              TextSpan(text: '${q}p'),
              if (size.isNotEmpty)
                TextSpan(
                  text: '  · $size',
                  style: TextStyle(
                      fontSize: 11,
                      color: (sel ? UiColors.text : UiColors.textDim)
                          .withOpacity(.6)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _downloadButton() {
    return Material(
      color: UiColors.accent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _startDownload,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.download_outlined,
                  color: Colors.white, size: 17),
              const SizedBox(width: 8),
              Text(
                'Скачать в $_selected p',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyTab() {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        if (appState.history.isEmpty) {
          return emptyState(Icons.history, 'История поиска пока пуста');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
          itemCount: appState.history.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final h = appState.history[i];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                _input.text = h;
                _tabs.animateTo(0);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: UiColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: UiColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history,
                        color: UiColors.textDim, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        h,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, color: UiColors.text),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
