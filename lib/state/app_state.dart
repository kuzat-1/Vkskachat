import 'package:flutter/foundation.dart';

class DownloadItem {
  DownloadItem({
    required this.id,
    required this.title,
    required this.quality,
    required this.sizeLabel,
    required this.filePath,
    this.progress = 0.0,
    this.done = false,
  });

  final String id;
  final String title;
  final String quality;
  final String sizeLabel;
  final String filePath;
  double progress; // 0..1
  bool done;
}

class AppState extends ChangeNotifier {
  final List<DownloadItem> downloads = [];
  final List<String> history = [];

  void addDownload(DownloadItem item) {
    downloads.insert(0, item);
    notifyListeners();
  }

  void updateProgress(String id, double p) {
    for (final d in downloads) {
      if (d.id == id) {
        d.progress = p < 0 ? 0 : (p > 1 ? 1 : p);
        notifyListeners();
        return;
      }
    }
  }

  void markDone(String id) {
    for (final d in downloads) {
      if (d.id == id) {
        d.done = true;
        d.progress = 1;
        notifyListeners();
        return;
      }
    }
  }

  void remove(String id) {
    downloads.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void addHistory(String q) {
    final s = q.trim();
    if (s.isEmpty) return;
    history.remove(s);
    history.insert(0, s);
    if (history.length > 20) history.removeLast();
    notifyListeners();
  }
}

final AppState appState = AppState();
