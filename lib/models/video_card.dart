import '../services/vk_api_service.dart';

/// Карточка видео в ленте (рекомендации / поиск).
/// duration — длительность в секундах (int от сервера).
class VideoCard {
  VideoCard({
    required this.id,
    required this.title,
    required this.thumb,
    required this.durationSec,
    required this.views,
  });

  final String id;
  final String title;
  final String thumb;
  final int durationSec;
  final int views;

  String get durationLabel => VkApiService.fmtDuration(durationSec);

  String get viewsLabel {
    if (views <= 0) return 'VK Видео';
    if (views >= 1000000) {
      final m = views / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1).replaceAll('.', ',')} млн просмотров';
    }
    if (views >= 1000) {
      final k = views / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1).replaceAll('.', ',')} тыс. просмотров';
    }
    return '$views просмотров';
  }

  factory VideoCard.fromMap(Map<String, dynamic> m) {
    return VideoCard(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      thumb: (m['thumb'] ?? '').toString(),
      durationSec: int.tryParse((m['duration'] ?? 0).toString()) ?? 0,
      views: int.tryParse((m['views'] ?? 0).toString()) ?? 0,
    );
  }
}
