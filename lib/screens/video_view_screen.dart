import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';
import '../models/video_card.dart';
import '../models/video_model.dart';
import '../services/download_service.dart';
import '../services/vk_api_service.dart';
import '../state/app_state.dart';
import '../ui_theme.dart';

/// Экран просмотра видео.
/// Если сервер отдал файлы (есть юзер-токен) — стримим mp4 через video_player.
/// Иначе — embed-плеер VK (video_ext.php) в WebView: видео играет в приложении.
class VideoViewScreen extends StatefulWidget {
  const VideoViewScreen({super.key, required this.card, required this.rawId});

  final VideoCard card;
  final String rawId;

  @override
  State<VideoViewScreen> createState() => _VideoViewScreenState();
}

class _VideoViewScreenState extends State<VideoViewScreen> {
  bool _loading = true;
  String? _error;
  String _title = '';
  String _thumb = '';
  int _durationSec = 0;
  int _views = 0;
  Map<String, String> _qualities = {};
  String _playerUrl = '';

  VideoPlayerController? _vc;
  final DownloadService _downloader = DownloadService();

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
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
        _qualities = Map<String, String>.from(
            (res['qualities'] as Map?) ?? const {});
        _playerUrl = (res['player'] as String?) ?? '';
        _title = (res['title'] as String?) ?? widget.card.title;
        _thumb = (res['thumb'] as String?) ?? widget.card.thumb;
        _durationSec =
            int.tryParse((res['duration'] ?? 0).toString()) ??
                widget.card.durationSec;
        _views = widget.card.views;
      });

      if (_qualities.isNotEmpty) {
        // стримим mp4
        const order = ['2160', '1440', '1080', '720', '480', '360', '240'];
        String? best;
        for (final q in order) {
          if (_qualities.containsKey(q)) {
            best = _qualities[q];
            break;
          }
        }
        if (best != null) {
          _vc = VideoPlayerController.networkUrl(Uri.parse(best));
          try {
            await _vc!.initialize();
            await _vc!.setLooping(false);
            await _vc!.play();
          } catch (_) {
            _vc?.dispose();
            _vc = null;
          }
        }
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Нет связи с сервером';
      });
    }
  }

  // ---------- СКАЧИВАНИЕ ----------

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
    return '~${((rates[q] ?? 1.0) * _durationSec).round()} МБ';
  }

  void _showQualityDialog() {
    if (_qualities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: UiColors.surface2,
          content: Text(
            'Ссылки на файл пока не выданы. Нужен ключ VK — '
            'см. token.html на сервере.',
            style: TextStyle(color: UiColors.text),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: UiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Качество для скачивания',
                style: TextStyle(
                    fontSize: 13,
                    color: UiColors.textDim,
                    letterSpacing: 0.7),
              ),
              const SizedBox(height: 10),
              ..._qualities.keys.map((q) {
                final size = _sizeFor(q);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _download(q, _qualities[q]!);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
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
                            Text(size,
                                style: const TextStyle(
                                    fontSize: 12, color: UiColors.textDim)),
                          const Icon(Icons.chevron_right,
                              color: UiColors.textDim, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: UiColors.surface2,
        content: Text(
          'Скачивание ${q}p запущено — смотри вкладку «Загрузки»',
          style: const TextStyle(color: UiColors.text),
        ),
      ),
    );

    int lastPercent = -1;
    try {
      final v = VideoModel(
        id: widget.card.id,
        title: _title.isEmpty ? 'Видео' : _title,
        thumbnailUrl: _thumb,
        videoUrl: '',
        channelName: 'VK Видео',
        views: _views,
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.bg,
      appBar: AppBar(
        backgroundColor: UiColors.bg,
        elevation: 0,
        centerTitle: false,
        title: Text(
          _title.isEmpty ? 'Видео' : _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: UiColors.text),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: UiColors.accent))
            : _error != null
                ? _errorView()
                : _content(),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 34, color: UiColors.textDim),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: UiColors.textDim, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            Material(
              color: UiColors.accent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _resolve,
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  child: Text('Повторить',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return Column(
      children: [
        // ПЛЕЕР
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: _player(),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title.isEmpty ? 'Видео VK' : _title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: UiColors.text),
                ),
                const SizedBox(height: 6),
                Text(
                  'VK Видео${_durationSec > 0 ? ' · ${VkApiService.fmtDuration(_durationSec)}' : ''}',
                  style: const TextStyle(
                      fontSize: 13, color: UiColors.textDim),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: UiColors.accent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _showQualityDialog,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.download_outlined,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                const Text('Скачать',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                if (_qualities.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '· ${_qualities.length} качества',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_qualities.isEmpty)
                  const Text(
                    'Ссылки на файл появятся после подключения ключа VK. '
                    'Видео уже доступно для просмотра — можно смотреть прямо здесь.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: UiColors.textDim,
                        height: 1.5),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _player() {
    if (_vc != null) {
      return AspectRatio(
        aspectRatio: _vc!.value.aspectRatio == 0
            ? 16 / 9
            : _vc!.value.aspectRatio,
        child: Container(
          color: Colors.black,
          child: VideoPlayer(_vc!),
        ),
      );
    }
    // WebView embed-плеер VK
    final url = _playerUrl.isNotEmpty
        ? _playerUrl
        : 'https://m.vk.com/video${widget.card.id}';
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
          ),
        ),
      ),
    );
  }
}
