import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import 'app/gadget_editor_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
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
