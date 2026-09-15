import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';

import '../models/video_card.dart';
import '../services/vk_api_service.dart';
import '../ui_theme.dart';

/// Экран просмотра VK Видео без скачивания.
/// При наличии прямых mp4-потоков используется собственный плеер
/// с управлением воспроизведением и качеством. Иначе — VK WebView.
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
  int _durationSec = 0;
  Map<String, String> _qualities = {};
  String _playerUrl = '';
  String _selectedQuality = 'Авто';
  bool _showControls = true;
  Timer? _hideTimer;
  VideoPlayerController? _vc;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
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

      _qualities = Map<String, String>.from((res['qualities'] as Map?) ?? const {});
      _playerUrl = (res['player'] as String?) ?? '';
      _title = (res['title'] as String?) ?? widget.card.title;
      _durationSec = int.tryParse((res['duration'] ?? 0).toString()) ?? widget.card.durationSec;

      await _openStream(_bestQuality());
      if (!mounted) return;
      setState(() => _loading = false);
      _startHideTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить видео. Проверьте интернет.';
      });
    }
  }

  String? _bestQuality() {
    const order = ['2160', '1440', '1080', '720', '480', '360', '240'];
    for (final q in order) {
      if (_qualities.containsKey(q)) return q;
    }
    return null;
  }

  Future<void> _openStream(String? quality) async {
    if (quality == null || !_qualities.containsKey(quality)) return;
    final url = _qualities[quality]!;
    await _vc?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _vc = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (identical(_vc, controller)) _vc = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _selectQuality(String value) async {
    Navigator.of(context).pop();
    if (value == 'Авто') {
      _selectedQuality = 'Авто';
      await _openStream(_bestQuality());
    } else {
      _selectedQuality = value;
      await _openStream(value.replaceAll('p', ''));
    }
    if (mounted) {
      setState(() {});
      _startHideTimer();
    }
  }

  List<String> _sortedQualities() {
    final list = _qualities.keys.toList();
    list.sort((a, b) => (int.tryParse(b) ?? 0).compareTo(int.tryParse(a) ?? 0));
    return list;
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_vc?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _togglePlay() {
    final c = _vc;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      c.play();
      setState(() => _showControls = true);
      _startHideTimer();
    }
  }

  void _showQualityDialog() {
    if (_qualities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для этого видео доступен встроенный VK-плеер.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: UiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Качество видео', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              const Text('Авто выбирает самое доступное качество.', style: TextStyle(color: UiColors.textDim, fontSize: 12)),
              const SizedBox(height: 12),
              _qualityTile(ctx, 'Авто', _selectedQuality == 'Авто'),
              ..._sortedQualities().map((q) => _qualityTile(ctx, '${q}p', _selectedQuality == '${q}p')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qualityTile(BuildContext ctx, String label, bool selected) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? UiColors.accent : UiColors.textDim),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () => _selectQuality(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.bg,
      appBar: AppBar(
        backgroundColor: UiColors.bg,
        elevation: 0,
        title: Text(_title.isEmpty ? 'Видео' : _title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: UiColors.accent))
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
            const Icon(Icons.error_outline, size: 40, color: UiColors.textDim),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: UiColors.textDim, height: 1.5)),
            const SizedBox(height: 18),
            FilledButton(onPressed: _resolve, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return Column(
      children: [
        _player(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title.isEmpty ? 'Видео VK' : _title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35)),
                const SizedBox(height: 7),
                Text('VK Видео${_durationSec > 0 ? ' · ${VkApiService.fmtDuration(_durationSec)}' : ''}', style: const TextStyle(fontSize: 13, color: UiColors.textDim)),
                const SizedBox(height: 16),
                if (_qualities.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _showQualityDialog,
                    icon: const Icon(Icons.high_quality_outlined, size: 19),
                    label: Text('Качество: $_selectedQuality'),
                  )
                else
                  const Text('Видео воспроизводится через встроенный VK-плеер.', style: TextStyle(color: UiColors.textDim, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _player() {
    if (_vc != null && _vc!.value.isInitialized) {
      final c = _vc!;
      return GestureDetector(
        onTap: _toggleControls,
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black, child: VideoPlayer(c)),
              if (_showControls)
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB8000000)]),
                  ),
                ),
              if (_showControls)
                Center(
                  child: IconButton(
                    onPressed: _togglePlay,
                    iconSize: 58,
                    color: Colors.white,
                    icon: Icon(c.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                  ),
                ),
              if (_showControls)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 4,
                  child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8), colors: const VideoProgressColors(playedColor: UiColors.accent, bufferedColor: Colors.white54, backgroundColor: Colors.white24)),
                ),
              if (_showControls && _qualities.length > 1)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _showQualityDialog,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        child: Text(_selectedQuality, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final url = _playerUrl.isNotEmpty ? _playerUrl : 'https://m.vk.com/video${widget.card.id}';
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: InAppWebViewSettings(javaScriptEnabled: true, mediaPlaybackRequiresUserGesture: false, allowsInlineMediaPlayback: true),
        ),
      ),
    );
  }
}
