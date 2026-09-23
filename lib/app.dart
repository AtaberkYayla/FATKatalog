import 'package:flutter/material.dart';

import 'storage/project_repository.dart';
import 'ui/projects/backup_menu.dart';
import 'ui/projects/projects_screen.dart';
import 'ui/scan/scan_controller.dart';
import 'ui/scan/scan_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/brand.dart';

class FatKatalogApp extends StatelessWidget {
  const FatKatalogApp({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FATKatalog',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: HomeShell(repository: repository),
    );
  }
}

/// Alt navigasyon: Okut · Projeler.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final _scan = ScanController(widget.repository);
  var _tab = 0;

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandTitle(),
        actions: [
          // Yedekleme yalnızca Projeler sekmesinde; Okut sekmesi sade kalsın.
          if (_tab == 1) BackupMenu(repository: widget.repository),
          const AboutButton(),
        ],
      ),
      // Kamera yalnızca Okut sekmesindeyken açık; son sonuç ScanController'da kalır.
      body: switch (_tab) {
        0 => ScanScreen(controller: _scan),
        _ => ProjectsScreen(repository: widget.repository),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Okut',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Projeler',
          ),
        ],
      ),
    );
  }
}
