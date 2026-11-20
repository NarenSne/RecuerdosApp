import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/auth.dart';
import 'data/reminders.dart';
import 'data/repository.dart';
import 'sync/mailbox_transport.dart';
import 'sync/supabase_transport.dart';
import 'sync/sync_service.dart';
import 'ui/auth_screen.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La app se usa siempre en vertical.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('es');
  Intl.defaultLocale = 'es';

  MailboxTransport? transport;
  if (AppConfig.syncEnabled) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    transport = SupabaseTransport();
  }

  final docs = await getApplicationDocumentsDirectory();
  final mediaDir = Directory(p.join(docs.path, 'media'));
  await mediaDir.create(recursive: true);
  final db = await Repository.openDb(
    p.join(await getDatabasesPath(), 'recuerditos.db'),
  );

  final repo = Repository(db, mediaDir);
  await repo.init();
  final sync = SyncService(repo: repo, transport: transport);
  await sync.init();
  final auth = AuthService(repo: repo, enabled: AppConfig.syncEnabled);
  await auth.init();
  final reminders = ReminderService(repo);
  try {
    await reminders.init();
  } catch (_) {
    // Sin recordatorios: el resto de la app funciona igual.
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: repo),
        ChangeNotifierProvider.value(value: sync),
        ChangeNotifierProvider.value(value: reminders),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: const RecuerditosApp(),
    ),
  );
}

class RecuerditosApp extends StatelessWidget {
  const RecuerditosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recuerditos',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Consumer2<AuthService, Repository>(
        builder: (_, auth, repo, __) {
          if (!auth.loggedIn) return const AuthScreen();
          if (repo.myName.isEmpty) return const NameSetupScreen();
          return const HomeScreen();
        },
      ),
    );
  }
}
