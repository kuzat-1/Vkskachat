// services/vk_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vk_video_downloader/models/video_model.dart';

class VkApiService {
  static const String _baseUrl = 'https://vkvideo.ru/api';
  
  // Получение видео по ссылке
  static Future<VideoModel?> getVideoByUrl(String videoUrl) async {
    try {
      final uri = Uri.parse(videoUrl);
      final videoId = _extractVideoId(uri.toString());
      
      final response = await http.get(
        Uri.parse('$_baseUrl/video/get?$videoId'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return VideoModel.fromJson(data['video']);
      }
    } catch (e) {
      print('Ошибка получения видео: $e');
    }
    return null;
  }

  // Поиск видео
  static Future<List<VideoModel>> searchVideos(String query, {int offset = 0}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/search?q=${Uri.encodeFull(query)}&offset=$offset'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> videos = data['videos'] as List<dynamic>? ?? [];
        return videos.map((json) => VideoModel.fromJson(json)).toList();
      }
    } catch (e) {
      print('Ошибка поиска видео: $e');
    }
    return [];
  }

  // Получение популярных видео
  static Future<List<VideoModel>> getTrendingVideos() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/trending'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> videos = data['videos'] as List<dynamic>? ?? [];
        return videos.map((json) => VideoModel.fromJson(json)).toList();
      }
    } catch (e) {
      print('Ошибка получения трендов: $e');
    }
    return [];
  }

  // Извлечение ID видео из ссылки
  static String _extractVideoId(String url) {
    // Поддержка ссылок вида vk.com/video-12345_67890, vkvideo.ru/video123_456
    final m = RegExp(r'video(-?\d+)_?(\d*)').firstMatch(url);
    if (m != null && m.group(1) != null) {
      final owner = m.group(1);
      final id = m.group(2) ?? '';
      return 'video$owner${id.isEmpty ? '' : '_$id'}';
    }

    final m2 = RegExp(r'[?&]v=([\w-]+)').firstMatch(url);
    if (m2 != null) return m2.group(1)!;

    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty && pathSegments.last.startsWith('video')) {
      return pathSegments.last;
    }

    final query = uri.queryParameters['v'];
    return query ?? '';
  }

  // Получение прямых ссылок на скачивание
  static Future<Map<String, String>> getDownloadLinks(String videoId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/video/download/$videoId'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final links = <String, String>{};
        final qualities = data['qualities'] as Map<String, dynamic>;
        
        for (final entry in qualities.entries) {
          links[entry.key] = entry.value as String;
        }
        
        return links;
      }
    } catch (e) {
      print('Ошибка получения ссылок для загрузки: $e');
    }
    return {};
  }
}