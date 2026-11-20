import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../sync/sync_service.dart';
import 'calendar_screen.dart';
import 'memories_screen.dart';
import 'partner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  /// Mientras la app está abierta, revisa el buzón cada minuto.
  void _startPolling() {
    final sync = context.read<SyncService>();
    sync.syncNow();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => sync.syncNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final waiting = sync.available && sync.paired && sync.lastError != null;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [MemoriesScreen(), CalendarScreen(), PartnerScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.photo_album_outlined),
            selectedIcon: Icon(Icons.photo_album),
            label: 'Recuerdos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: waiting,
              smallSize: 8,
              child: const Icon(Icons.favorite_border),
            ),
            selectedIcon: const Icon(Icons.favorite),
            label: 'Pareja',
          ),
        ],
      ),
    );
  }
}
