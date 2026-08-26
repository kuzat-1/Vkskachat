import 'package:flutter/material.dart';
import '../models/video_card.dart';
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

  // лента рекомендаций
  List<VideoCard> _feed = const [];
  bool _feedLoading = false;
  String? _feedError;
  String _feedCat = '';

  // поиск
  List<VideoCard> _results = const [];
  bool _searchLoading = false;
  String? _searchError;
  String _searchQuery = '';

  static const _cats = [
    ('', 'Все'),
    ('music', 'Музыка'),
    ('news', 'Новости'),
    ('funny', 'Приколы'),
    ('games', 'Игры'),
    ('sport', 'Спорт'),
    ('science', 'Наука'),
  ];

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _input.dispose();
    super.dispose();
  }

  // ---------- ЛОГИКА ----------

  Future<void> _loadFeed() async {
    if (_feedLoading) return;
    setState(() {
      _feedLoading = true;
      _feedError = null;
    });
    try {
      final rs = await VkApiService.recommendations(cat: _feedCat, limit: 14);
      if (!mounted) return;
      setState(() {
        _feedLoading = false;
        _feed = rs.map(VideoCard.fromMap).toList();
        if (_feed.isEmpty) {
          _feedError = VkApiService.lastError?.isNotEmpty == true
              ? 'Не удалось загрузить ленту.\n${VkApiService.lastError}'
              : 'Лента пока пуста. Потяните вниз, чтобы обновить.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedLoading = false;
        _feedError = 'Нет связи с сервером. Проверьте интернет.';
      });
    }
  }

  Future<void> _pickCat(String cat) async {
    if (cat == _feedCat) return;
    setState(() {
      _feedCat = cat;
      _feed = const [];
    });
    await _loadFeed();
  }

  Future<void> _goSearch() async {
    final raw = _input.text.trim();
    if (raw.isEmpty || _searchLoading) return;

    appState.addHistory(raw);
    _tabs.animateTo(1);

    if (VkApiService.looksLikeLinkOrId(raw)) {
      final id = VkApiService.normalizeVideoId(raw);
      if (id != null) {
        final card = VideoCard(
          id: id,
          title: 'Видео по ссылке',
          thumb: '',
          durationSec: 0,
          views: 0,
        );
        await _openVideo(card, raw);
        return;
      }
    }

    setState(() {
      _searchLoading = true;
      _searchError = null;
      _searchQuery = raw;
      _results = const [];
    });
    try {
      final rs = await VkApiService.search(raw);
      if (!mounted) return;
      setState(() {
        _searchLoading = false;
        _results = rs.map(VideoCard.fromMap).toList();
        if (_results.isEmpty) {
          _searchError = VkApiService.lastError?.isNotEmpty == true
              ? 'Поиск не дал результатов.\n${VkApiService.lastError}'
              : 'Ничего не найдено. Попробуйте другой запрос.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchLoading = false;
        _searchError = 'Поиск временно не работает. Попробуйте позже.';
      });
    }
  }

  /// Открыть видео: резолв → лист с качеством → скачивание
  Future<void> _openVideo(VideoCard card, String rawId) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ResolveDialog(card: card, rawId: rawId),
    );
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
                Tab(text: 'Рекомендации'),
                Tab(text: 'Поиск'),
                Tab(text: 'История'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _feedTab(),
                  _searchTab(),
                  _historyTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ ТАБ «РЕКОМЕНДАЦИИ» ============

  Widget _feedTab() {
    return Column(
      children: [
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (key, label) = _cats[i];
              final sel = key == _feedCat;
              return GestureDetector(
                onTap: () => _pickCat(key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? UiColors.accentSoft : UiColors.surface,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: sel ? UiColors.accent : UiColors.border),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      color: sel ? UiColors.text : UiColors.textDim,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: UiColors.accent,
            backgroundColor: UiColors.surface,
            onRefresh: _loadFeed,
            child: _feedLoading && _feed.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: CircularProgressIndicator(color: UiColors.accent),
                    ),
                  )
                : _feedError != null && _feed.isEmpty
                    ? _feedErrorView()
                    : _feedList(),
          ),
        ),
      ],
    );
  }

  Widget _feedErrorView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      children: [
        const Icon(Icons.cloud_off, size: 40, color: UiColors.textDim),
        const SizedBox(height: 14),
        Text(
          _feedError!,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: UiColors.textDim, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 18),
        Center(
          child: Material(
            color: UiColors.accent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _loadFeed,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                child: Text('Повторить',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _feedList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      itemCount: _feed.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, i) => _videoCard(_feed[i]),
    );
  }

  // ============ ТАБ «ПОИСК» ============

  Widget _searchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          _searchBox(),
          const SizedBox(height: 22),
          if (_searchLoading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: CircularProgressIndicator(color: UiColors.accent),
              ),
            )
          else if (_searchError != null && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _searchError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: UiColors.textDim, fontSize: 13, height: 1.5),
              ),
            )
          else if (_results.isNotEmpty)
            _resultsList()
          else
            _hintBlock(),
        ],
      ),
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
          const Icon(Icons.search, color: UiColors.textDim, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _input,
              style: const TextStyle(color: UiColors.text, fontSize: 15),
              decoration: const InputDecoration.collapsed(
                hintText: 'Название видео или ссылка',
                hintStyle:
                    TextStyle(color: UiColors.textDim, fontSize: 15),
              ),
              onSubmitted: (_) => _goSearch(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _goSearch,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: UiColors.accent, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_forward,
                  color: Colors.white, size: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintBlock() {
    return Padding(
      padding: const EdgeInsets.only(left: 40, right: 40, top: 44),
      child: Column(
        children: [
          const Icon(Icons.desktop_windows_outlined,
              size: 40, color: UiColors.textDim),
          const SizedBox(height: 14),
          const Text(
            'Введите название видео — найдём его\nна VK и покажем карточки для скачивания',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: UiColors.textDim, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 6),
          const Text(
            'сборка 16 · лента VK',
            style: TextStyle(
                fontFamily: kMono, fontSize: 10, color: UiColors.textDim),
          ),
        ],
      ),
    );
  }

  Widget _resultsList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              '«${_searchQuery.isEmpty ? '...' : _searchQuery}» — найдено',
              style: const TextStyle(
                  fontSize: 12,
                  color: UiColors.textDim,
                  letterSpacing: 0.7),
            ),
          ),
          ..._results.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _videoCard(r),
              )),
        ],
      ),
    );
  }

  // ============ КАРТОЧКА ============

  Widget _videoCard(VideoCard card) {
    final String vkUrl = 'https://vk.com/video${card.id}';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openVideo(card, vkUrl),
      child: Container(
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
                  if (card.thumb.isNotEmpty)
                    Image.network(
                      card.thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                    )
                  else
                    _thumbPlaceholder(),
                  // длительность
                  if (card.durationSec > 0)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xCC000000),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          card.durationLabel,
                          style: const TextStyle(
                              fontFamily: kMono,
                              fontSize: 11,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  // иконка скачивания в углу
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _openVideo(card, vkUrl),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xCC12161F),
                          shape: BoxShape.circle,
                          border: Border.all(color: UiColors.border),
                        ),
                        child: const Icon(Icons.download_outlined,
                            color: UiColors.amber, size: 19),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title.isEmpty ? 'Видео ${card.id}' : card.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: UiColors.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    card.viewsLabel,
                    style: const TextStyle(
                        fontSize: 12, color: UiColors.textDim),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      child: const Center(
        child: Icon(Icons.play_circle_outline,
            color: UiColors.textDim, size: 30),
      ),
    );
  }

  // ============ ИСТОРИЯ ============

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
                _tabs.animateTo(1);
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

/// Диалог-резолвер: крутится, пока сервер отдаёт качества, потом лист качества.
class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({required this.card, required this.rawId});

  final VideoCard card;
  final String rawId;

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  bool _loading = true;
  String? _error;
  Map<String, String> _qualities = {};
  String _title = '';
  String _thumb = '';
  int _durationSec = 0;
  final DownloadService _downloader = DownloadService();

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await VkApiService.resolve(widget.rawId);
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _loading = false;
          _error = VkApiService.lastError ?? 'Не удалось открыть видео';
        });
        return;
      }
      setState(() {
        _loading = false;
        _qualities = Map<String, String>.from(
            (res['qualities'] as Map?) ?? const {});
        _title = (res['title'] as String?) ?? widget.card.title;
        _thumb = (res['thumb'] as String?) ?? widget.card.thumb;
        _durationSec =
            int.tryParse((res['duration'] ?? 0).toString()) ??
                widget.card.durationSec;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Нет связи с сервером';
      });
    }
  }

  String _sizeFor(String q) {
    const rates = {
      '240': 0.35,
      '360': 0.6,
      '480': 0.95,
      '720': 1.6,
      '1080': 2.6,
      '1440': 4.5,
      '2160': 8.0,
    };
    if (_durationSec <= 0) return '';
    final mb = ((rates[q] ?? 1.0) * _durationSec).round();
    return '~$mb МБ';
  }

  Future<void> _download(String q, String url) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final item = DownloadItem(
      id: id,
      title: _title.isEmpty ? 'Видео' : _title,
      quality: '${q}p',
      sizeLabel: _sizeFor(q),
      filePath: '',
    );
    appState.addDownload(item);
    Navigator.of(context).pop(); // закрыть диалог

    int lastPercent = -1;
    try {
      final v = VideoModel(
        id: widget.card.id,
        title: _title.isEmpty ? 'Видео' : _title,
        thumbnailUrl: _thumb,
        videoUrl: '',
        channelName: 'VK Видео',
        views: 0,
        duration: VkApiService.fmtDuration(_durationSec),
        qualities: [],
      );
      final path = await _downloader.downloadVideo(v, q, url, (rec, tot) {
        if (tot <= 0) return;
        final pct = (rec / tot * 100).floor();
        if (pct != lastPercent) {
          lastPercent = pct;
          appState.updateProgress(id, rec / tot);
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
            content:
                Text('Ошибка скачивания', style: TextStyle(color: UiColors.text)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: UiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.maxFinite,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: UiColors.accent),
                ),
              )
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 32, color: UiColors.textDim),
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: UiColors.textDim, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Material(
                            color: UiColors.surface2,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _resolve,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 9),
                                child: Text('Повторить',
                                    style: TextStyle(
                                        color: UiColors.text,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: UiColors.surface2,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.of(context).pop(),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 9),
                                child: Text('Закрыть',
                                    style: TextStyle(
                                        color: UiColors.textDim,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : _qualitySheet(),
      ),
    );
  }

  Widget _qualitySheet() {
    final bool noLinks = _qualities.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // превью
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_thumb.isNotEmpty)
                  Image.network(
                    _thumb,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _thumbPh(),
                  )
                else
                  _thumbPh(),
                if (_durationSec > 0)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        VkApiService.fmtDuration(_durationSec),
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
        ),
        const SizedBox(height: 12),
        Text(
          _title.isEmpty ? 'Видео VK' : _title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: UiColors.text),
        ),
        const SizedBox(height: 4),
        const Text('VK Видео',
            style: TextStyle(fontSize: 12, color: UiColors.textDim)),
        const SizedBox(height: 14),
        if (noLinks)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: UiColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: UiColors.accent),
            ),
            child: const Text(
              'Видео нашлось, но ссылки на файл ещё не выданы. '
              'Мы подключаем полный доступ — попробуй позже '
              'или другое видео.',
              style: TextStyle(
                  fontSize: 13, height: 1.45, color: UiColors.text),
            ),
          )
        else ...[
          const Text(
            'Качество для скачивания',
            style: TextStyle(
                fontSize: 12, color: UiColors.textDim, letterSpacing: 0.7),
          ),
          const SizedBox(height: 10),
          ..._qualities.keys.map((q) {
            final size = _sizeFor(q);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _download(q, _qualities[q]!),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: UiColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: UiColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.download_outlined,
                          color: UiColors.amber, size: 17),
                      const SizedBox(width: 10),
                      Text(
                        '${q}p',
                        style: const TextStyle(
                            fontFamily: kMono,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: UiColors.text),
                      ),
                      const Spacer(),
                      if (size.isNotEmpty)
                        Text(
                          size,
                          style: const TextStyle(
                              fontSize: 12, color: UiColors.textDim),
                        ),
                      const Icon(Icons.chevron_right,
                          color: UiColors.textDim, size: 18),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ],
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть',
                style: TextStyle(color: UiColors.textDim)),
          ),
        ),
      ],
    );
  }

  Widget _thumbPh() {
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
}
