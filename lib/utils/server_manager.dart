// utils/server_manager.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:vk_video_downloader/models/video_model.dart';
import 'package:vk_video_downloader/services/vk_api_service.dart';

class ServerManager {
  static HttpServer? _server;
  static const int _port = 8080;

  // Запуск локального сервера
  static Future<void> startServer() async {
    if (_server != null) {
      print('Сервер уже запущен на порту $_port');
      return;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _server!.listen(_handleRequest);
      print('Локальный сервер запущен на порту $_port');
    } catch (e) {
      print('Ошибка запуска сервера: $e');
    }
  }

  // Обработка запросов к серверу
  static void _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    try {
      if (method == 'GET' && path == '/') {
        _sendResponse(request, 200, {'message': 'VK Video Downloader API'});
      } else if (method == 'GET' && path.startsWith('/video/')) {
        await _handleVideoRequest(request);
      } else if (method == 'GET' && path == '/search') {
        await _handleSearchRequest(request);
      } else if (method == 'GET' && path == '/trending') {
        await _handleTrendingRequest(request);
      } else if (method == 'GET' && path.startsWith('/download/')) {
        await _handleDownloadRequest(request);
      } else {
        _sendResponse(request, 404, {'error': 'Маршрут не найден'});
      }
    } catch (e) {
      print('Ошибка обработки запроса: $e');
      _sendResponse(request, 500, {'error': 'Внутренняя ошибка сервера'});
    }
  }

  // Обработка запроса видео по ID
  static Future<void> _handleVideoRequest(HttpRequest request) async {
    final videoId = request.uri.path.split('/').last;
    
    // Если это ссылка на VK видео
    if (videoId.contains('video')) {
      final video = await VkApiService.getVideoByUrl('https://vkvideo.ru/$videoId');
      if (video != null) {
        _sendJsonResponse(request, 200, {'video': video.toJson()});
      } else {
        _sendResponse(request, 404, {'error': 'Видео не найдено'});
      }
    } else {
      // Прямой запрос по ID
      final downloadLinks = await VkApiService.getDownloadLinks(videoId);
      if (downloadLinks.isNotEmpty) {
        _sendJsonResponse(request, 200, {
          'qualities': downloadLinks,
          'id': videoId,
        });
      } else {
        _sendResponse(request, 404, {'error': 'Ссылки для загрузки не найдены'});
      }
    }
  }

  // Обработка запроса поиска
  static Future<void> _handleSearchRequest(HttpRequest request) async {
    final query = request.uri.queryParameters['q'] ?? '';
    final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '0') ?? 0;
    
    if (query.isEmpty) {
      _sendResponse(request, 400, {'error': 'Параметр q обязателен'});
      return;
    }

    final videos = await VkApiService.searchVideos(query, offset: offset);
    
    final response = {
      'videos': videos.map((v) => v.toJson()).toList(),
      'count': videos.length,
    };
    
    _sendJsonResponse(request, 200, response);
  }

  // Обработка запроса трендов
  static Future<void> _handleTrendingRequest(HttpRequest request) async {
    final videos = await VkApiService.getTrendingVideos();
    
    final response = {
      'videos': videos.map((v) => v.toJson()).toList(),
      'count': videos.length,
    };
    
    _sendJsonResponse(request, 200, response);
  }

  // Обработка запроса загрузки
  static Future<void> _handleDownloadRequest(HttpRequest request) async {
    final videoId = request.uri.path.split('/').last;
    final downloadLinks = await VkApiService.getDownloadLinks(videoId);
    
    if (downloadLinks.isNotEmpty) {
      _sendJsonResponse(request, 200, {'qualities': downloadLinks});
    } else {
      _sendResponse(request, 404, {'error': 'Ссылки не найдены'});
    }
  }

  // Отправка JSON ответа
  static void _sendJsonResponse(HttpRequest request, int statusCode, Map<String, dynamic> data) {
    final jsonResponse = json.encode(data);
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonResponse)
      ..close();
  }

  // Отправка текстового ответа
  static void _sendResponse(HttpRequest request, int statusCode, Map<String, dynamic> data) {
    final jsonResponse = json.encode(data);
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonResponse)
      ..close();
  }

  // Остановка сервера
  static Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
      print('Сервер остановлен');
    }
  }

  // Получение адреса сервера
  static String get serverUrl => 'http://localhost:$_port';
}