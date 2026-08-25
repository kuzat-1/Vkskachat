import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../ui_theme.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.bg,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            final items = appState.downloads;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Row(
                    children: [
                      const Text(
                        'Загрузки',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: UiColors.text),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: UiColors.border),
                        ),
                        child: Text(
                          filesLabel(items.length),
                          style: const TextStyle(
                              fontFamily: kMono,
                              fontSize: 11,
                              color: UiColors.textDim),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? emptyState(Icons.download_outlined,
                          'Скачанные видео появятся здесь')
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(20, 4, 20, 110),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _row(context, items[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, DownloadItem d) {
    final p = d.progress;
    final w = p < 0 ? 0.0 : (p > 1 ? 1.0 : p);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: (d.done && d.filePath.isNotEmpty)
          ? () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayerScreen(item: d)))
          : null,
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
                    d.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: UiColors.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${d.quality} · ${d.sizeLabel}',
                    style: const TextStyle(
                        fontFamily: kMono,
                        fontSize: 11,
                        color: UiColors.textDim),
                  ),
                  if (!d.done) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 4,
                        color: UiColors.border,
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: w,
                          child: Container(color: UiColors.amber),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Готово',
                      style: TextStyle(
                          fontFamily: kMono,
                          fontSize: 11,
                          color: UiColors.amber),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => appState.remove(d.id),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: UiColors.border),
                ),
                child: const Icon(Icons.close,
                    color: UiColors.textDim, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
