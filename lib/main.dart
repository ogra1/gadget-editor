import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import 'app/gadget_editor_screen.dart';
import 'services/snap_store_service.dart';
import 'services/snap_file_service.dart';
import 'services/snap_pack_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
          // Construct the production services once and inject them so the
          // screen itself stays free of concrete-service wiring (testable).
          home: GadgetEditorScreen(
            storeService: SnapStoreService(),
            fileService: SnapFileService(),
            packService: SnapPackService(),
          ),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
