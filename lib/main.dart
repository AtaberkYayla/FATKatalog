import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'storage/project_repository.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Android: filesDir/projects/
  final support = await getApplicationSupportDirectory();
  final repository = ProjectRepository(
    Directory('${support.path}/projects'),
    headerStyle: excelHeaderStyle,
  );

  runApp(FatKatalogApp(repository: repository));
}
