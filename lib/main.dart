import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import 'app/gadget_editor_screen.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(800, 600),
    center: true,
    titleBarStyle: TitleBarStyle.normal,
  );  

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  }); 

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    
    // Intercepts the rendering lifecycle after the core framework paint operation completes
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Small native duration ensures Wayland acknowledges application frame delivery
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Override the maximized container setting
      await windowManager.unmaximize();
      await windowManager.setSize(const Size(1280, 720));
      await windowManager.center();
    });
  }

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      data: const YaruThemeData(
        variant: YaruVariant.orange,
      ),
      builder: (context, yaru, child) {
        return MaterialApp(
          title: 'Gadget Editor',
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          themeMode: ThemeMode.system,
          home: const GadgetEditorScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
