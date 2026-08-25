import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'services/vk_api_service.dart';
import 'ui_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    VkApiService.token = prefs.getString('vk_token');
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: UiColors.bg,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Видеозагрузчик',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: UiColors.bg,
        colorScheme: const ColorScheme.dark(primary: UiColors.accent),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) => Scaffold(
        backgroundColor: UiColors.bg,
        body: IndexedStack(
          index: _tab,
          children: [
            HomeScreen(onGoToDownloads: () => setState(() => _tab = 1)),
            const DownloadsScreen(),
          ],
        ),
        bottomNavigationBar: _buildNav(appState.downloads.length),
      ),
    );
  }

  Widget _buildNav(int count) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF50A0D12),
        border: Border(top: BorderSide(color: UiColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _navButton(0, Icons.search_outlined, Icons.search),
              _navButton(1, Icons.download_outlined, Icons.download,
                  badge: count),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButton(int index, IconData outlined, IconData filled,
      {int badge = 0}) {
    final bool active = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                active ? filled : outlined,
                size: 26,
                color: active ? UiColors.text : UiColors.textDim,
              ),
              if (index == 1 && badge > 0)
                Positioned(
                  top: -7,
                  right: -9,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 14, minHeight: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: UiColors.amber,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: UiColors.bg, width: 2),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: UiColors.bg,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
