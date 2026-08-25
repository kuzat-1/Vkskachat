import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../state/app_state.dart';
import '../ui_theme.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.item});

  final DownloadItem item;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late DownloadItem _current = widget.item;
  VideoPlayerController? _ctrl;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open(_current);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _open(DownloadItem it) async {
    final old = _ctrl;
    _ctrl = null;
    if (mounted) {
      setState(() {
        _failed = false;
        _current = it;
      });
    }
    await old?.dispose();

    if (it.filePath.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final f = File(it.filePath);
    if (!await f.exists()) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final c = VideoPlayerController.file(f);
    try {
      await c.initialize();
      await c.play();
      c.addListener(_onTick);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctrl = c);
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    final ready = c != null && c.value.isInitialized;
    double pos = 0;
    if (ready) {
      final durMs = c.value.duration.inMilliseconds;
      pos = durMs > 0 ? c.value.position.inMilliseconds / durMs : 0.0;
      if (pos < 0) pos = 0;
      if (pos > 1) pos = 1;
    }

    final others = appState.downloads
        .where((d) => d.id != _current.id && d.done && d.filePath.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: UiColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: UiColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: UiColors.border),
                      ),
                      child: const Icon(Icons.chevron_left,
                          color: UiColors.text, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Просмотр',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: UiColors.textDim),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [UiColors.surface2, UiColors.border],
                      ),
                    ),
                  ),
                  if (ready)
                    GestureDetector(
                      onTap: _toggle,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: c.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c),
                        ),
                      ),
                    ),
                  if (ready && !c.value.isPlaying)
                    Center(
                      child: GestureDetector(
                        onTap: _toggle,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: UiColors.playCircle,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow,
                              color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  if (!ready)
                    Center(
                      child: _failed
                          ? const Text(
                              'Файл недоступен',
                              style: TextStyle(
                                  color: UiColors.textDim, fontSize: 13),
                            )
                          : const CircularProgressIndicator(
                              color: UiColors.accent, strokeWidth: 2),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 3,
                      color: const Color(0x33FFFFFF),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: pos,
                        child: Container(color: UiColors.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _current.title,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: UiColors.text),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_current.quality} · ${_current.sizeLabel}',
                      style: const TextStyle(
                          fontFamily: kMono,
                          fontSize: 12,
                          color: UiColors.textDim),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Другие загрузки',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: UiColors.textDim,
                          letterSpacing: 0.7),
                    ),
                    const SizedBox(height: 12),
                    if (others.isEmpty)
                      const Text(
                        'Других загруженных видео пока нет',
                        style:
                            TextStyle(color: UiColors.textDim, fontSize: 13),
                      )
                    else
                      ...others.map((o) => _otherRow(o)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _otherRow(DownloadItem o) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open(o),
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
            Container(
              width: 100,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [UiColors.surface2, UiColors.border],
                ),
              ),
              child: const Icon(Icons.play_arrow,
                  color: UiColors.textDim, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: UiColors.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${o.quality} · ${o.sizeLabel}',
                    style: const TextStyle(
                        fontFamily: kMono,
                        fontSize: 11,
                        color: UiColors.textDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
