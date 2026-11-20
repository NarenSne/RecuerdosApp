import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Paleta "Papel y girasol": fondo crema, texto tinta y un solo acento
/// amarillo. El amarillo puro (#D9A21B) no se lee sobre crema, así que en
/// textos y botones se usa su versión ocre.
ColorScheme _paperScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFFD9A21B),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  if (brightness == Brightness.light) {
    return base.copyWith(
      primary: const Color(0xFF8A6410),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFFF5E6BC),
      onPrimaryContainer: const Color(0xFF3D2C05),
      secondary: const Color(0xFF6B665E),
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFEFEADF),
      onSecondaryContainer: const Color(0xFF1F1D1A),
      tertiary: const Color(0xFF8C857A),
      onTertiary: const Color(0xFFFFFFFF),
      tertiaryContainer: const Color(0xFFEFEADF),
      onTertiaryContainer: const Color(0xFF1F1D1A),
      surface: const Color(0xFFFAF8F3),
      onSurface: const Color(0xFF1F1D1A),
      onSurfaceVariant: const Color(0xFF6B665E),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFFFFFF),
      surfaceContainer: const Color(0xFFF4F1EA),
      surfaceContainerHigh: const Color(0xFFEFEBE3),
      surfaceContainerHighest: const Color(0xFFE9E5DC),
      outline: const Color(0xFFA39D92),
      outlineVariant: const Color(0xFFE8E4DC),
    );
  }
  return base.copyWith(
    primary: const Color(0xFFE9B949),
    onPrimary: const Color(0xFF2B1F05),
    primaryContainer: const Color(0xFF4A3A12),
    onPrimaryContainer: const Color(0xFFF6E3B0),
    secondary: const Color(0xFFA8A196),
    onSecondary: const Color(0xFF1F1D1A),
    secondaryContainer: const Color(0xFF34312C),
    onSecondaryContainer: const Color(0xFFEDE9E1),
    tertiary: const Color(0xFFA8A196),
    onTertiary: const Color(0xFF1F1D1A),
    tertiaryContainer: const Color(0xFF34312C),
    onTertiaryContainer: const Color(0xFFEDE9E1),
    surface: const Color(0xFF161513),
    onSurface: const Color(0xFFEDE9E1),
    onSurfaceVariant: const Color(0xFFA8A196),
    surfaceContainerLowest: const Color(0xFF100F0E),
    surfaceContainerLow: const Color(0xFF1E1C1A),
    surfaceContainer: const Color(0xFF232120),
    surfaceContainerHigh: const Color(0xFF2A2825),
    surfaceContainerHighest: const Color(0xFF33302C),
    outline: const Color(0xFF7A7469),
    outlineVariant: const Color(0xFF34312C),
  );
}

/// Texto general.
const bodyFont = 'Inter';

/// Títulos y "RECUERDOS con:".
const titleFont = 'Fraunces';

/// Nombres: el apodo de la pareja y el nombre de la app (Fraunces en
/// cursiva).
const scriptFont = 'Fraunces';

ThemeData buildTheme(Brightness brightness) {
  final scheme = _paperScheme(brightness);
  final plain = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: bodyFont,
  );
  // Títulos grandes en Fraunces; el resto en Inter, sobria y legible.
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
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
