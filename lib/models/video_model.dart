// models/video_model.dart
class VideoModel {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String videoUrl;
  final String channelName;
  final int views;
  final String duration;
  final List<String> qualities;
  final int sizeBytes;
  
  VideoModel({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.videoUrl,
    required this.channelName,
    required this.views,
    required this.duration,
    required this.qualities,
    this.sizeBytes = 0,
  });
  
  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      thumbnailUrl: json['thumbnail'] as String? ?? '',
      videoUrl: json['url'] as String? ?? '',
      channelName: json['channel'] as String? ?? '',
      views: json['views'] as int? ?? 0,
      duration: json['duration'] as String? ?? '0:00',
      qualities: json['qualities'] != null 
          ? List<String>.from(json['qualities']) 
          : ['360p', '720p', '1080p'],
      sizeBytes: json['size'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'thumbnail': thumbnailUrl,
      'url': videoUrl,
      'channel': channelName,
      'views': views,
      'duration': duration,
      'qualities': qualities,
      'size': sizeBytes,
    };
  }

  VideoModel copyWith({
    String? id,
    String? title,
    String? thumbnailUrl,
    String? videoUrl,
    String? channelName,
    int? views,
    String? duration,
    List<String>? qualities,
    int? sizeBytes,
  }) {
    return VideoModel(
      id: id ?? this.id,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      channelName: channelName ?? this.channelName,
      views: views ?? this.views,
      duration: duration ?? this.duration,
      qualities: qualities ?? this.qualities,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }
}