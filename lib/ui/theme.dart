import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Terracota: cálido, como una foto impresa. Un solo acento en toda la app.
const _seed = Color(0xFFB4533C);

/// Texto general.
const bodyFont = 'Nunito';

/// Títulos y "RECUERDOS con:".
const titleFont = 'Playfair Display';

/// Nombres: el apodo de la pareja y el nombre de la app.
const scriptFont = 'Dancing Script';

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final plain = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: bodyFont,
  );
  // Títulos grandes en serif elegante; el resto en Nunito, redonda y legible.
  TextStyle? serif(TextStyle? s) =>
      s?.copyWith(fontFamily: titleFont, fontWeight: FontWeight.w600);
  final t = plain.textTheme;
  final textTheme = t.copyWith(
    displayLarge: serif(t.displayLarge),
    displayMedium: serif(t.displayMedium),
    displaySmall: serif(t.displaySmall),
    headlineLarge: serif(t.headlineLarge),
    headlineMedium: serif(t.headlineMedium),
    headlineSmall: serif(t.headlineSmall),
    titleLarge: serif(t.titleLarge),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );
  final base = plain.copyWith(textTheme: textTheme);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
  );
}

String formatDate(DateTime d) =>
    DateFormat("d 'de' MMMM 'de' y", 'es').format(d);

String formatDayLong(DateTime d) =>
    toBeginningOfSentenceCase(DateFormat("EEEE d 'de' MMMM", 'es').format(d));

String formatMonthYear(DateTime d) =>
    toBeginningOfSentenceCase(DateFormat("MMMM 'de' y", 'es').format(d));

String formatTime(DateTime d) => DateFormat.Hm('es').format(d);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

Future<void> openInMaps(
  BuildContext context, {
  required String place,
  double? lat,
  double? lng,
}) async {
  final query = lat != null && lng != null ? '$lat,$lng' : place;
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No se pudo abrir el mapa.')));
  }
}
