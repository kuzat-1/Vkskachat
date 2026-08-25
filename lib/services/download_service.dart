// services/download_service.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vk_video_downloader/models/video_model.dart';
import 'package:vk_video_downloader/services/vk_api_service.dart';

class DownloadService {
  final Dio _dio = Dio();
  final Set<String> _activeDownloads = {};

  Future<String?> downloadVideo(
    VideoModel video,
    String quality,
    Function(int received, int total) onProgress,
  ) async {
    final downloadLinks = await VkApiService.getDownloadLinks(video.id);
    final url = downloadLinks[quality];
    
    if (url == null) {
      throw Exception('Ссылка для качества $quality не найдена');
    }

    final dir = await getApplicationDocumentsDirectory();
    final savedDir = Directory('${dir.path}/videos');
    await savedDir.create(recursive: true);

    final fileName = '${video.id}_$quality.mp4';
    final filePath = '${savedDir.path}/$fileName';

    _activeDownloads.add(filePath);

    try {
      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total * 100).round();
            onProgress(received, total);
            print('Загрузка $fileName: $progress%');
          }
        },
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      _activeDownloads.remove(filePath);
      return filePath;
    } catch (e) {
      _activeDownloads.remove(filePath);
      print('Ошибка загрузки: $e');
      throw Exception('Не удалось загрузить видео: $e');
    }
  }

  bool isDownloading(String filePath) {
    return _activeDownloads.contains(filePath);
  }

  void cancelDownload(String filePath) {
    _activeDownloads.remove(filePath);
  }
}