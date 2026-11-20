/// Configuración del buzón temporal (Supabase).
///
/// Los recuerdos se guardan SIEMPRE en el teléfono. Supabase solo se usa como
/// buzón: cada cambio viaja cifrado y se borra en cuanto la pareja lo recibe.
///
/// Pon aquí los datos de tu proyecto (Supabase → Project Settings → API
/// Keys), o pásalos al compilar:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
///
/// Todos estos valores son públicos (viajan dentro de la app). Nunca pongas
/// aquí la "secret key" de Supabase, la contraseña de la base de datos ni el
/// secreto del cliente de Google.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nezzryrqmusugcbnvyyk.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_GEwvmCAumYv0xO7-GrMwzA_b8UmiCn7',
  );

  static bool get syncEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Inicio de sesión con Google (Google Cloud → Credenciales → IDs de
  /// cliente OAuth). El "web" es el que se pega también en Supabase.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '1011987525189-t6jp38dkhl1809s5rrt4vl3jhensr5k3.apps.googleusercontent.com',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue:
        '1011987525189-29s0ss42c6c4tb0lbofmik042vvm19jk.apps.googleusercontent.com',
  );

  static bool get googleEnabled => googleWebClientId.isNotEmpty;

  /// El plan gratuito de Supabase acepta archivos de hasta 50 MB. Dejamos
  /// margen para el cifrado. Videos más grandes se quedan solo en el teléfono.
  static const maxShareBytes = 45 * 1024 * 1024;
}
