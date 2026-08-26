import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vk_video_downloader/models/video_model.dart';

class DownloadService {
  final Dio _dio = Dio();

  Future<String?> downloadVideo(
    VideoModel video,
    String quality,
    String directUrl,
    Function(int received, int total) onProgress,
  ) async {
    if (directUrl.isEmpty) {
      throw Exception('Нет ссылки для качества $quality');
    }

    final dir = await getApplicationDocumentsDirectory();
    final savedDir = Directory('${dir.path}/videos');
    await savedDir.create(recursive: true);

    final safeId = video.id.replaceAll(RegExp(r'[^\w-]'), '_');
    final fileName = '${safeId}_$quality.mp4';
    final filePath = '${savedDir.path}/$fileName';

    try {
      await _dio.download(
        directUrl,
        filePath,
        onReceiveProgress: onProgress,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          },
        ),
      );
      return filePath;
    } catch (e) {
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      throw Exception('Ошибка загрузки: $e');
    }
  }
}
