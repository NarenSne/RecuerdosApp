import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../config.dart';
import 'repository.dart';

/// Error de inicio de sesión con un mensaje listo para mostrar.
class LoginException implements Exception {
  const LoginException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// El usuario cerró la ventana de Google: no es un error.
class LoginCanceled implements Exception {
  const LoginCanceled();
}

/// Inicio de sesión con Google (gratis). Las cuentas las maneja Supabase
/// Auth; los recuerdos siguen guardados solo en el teléfono.
class AuthService extends ChangeNotifier {
  AuthService({required this.repo, required this.enabled});

  final Repository repo;

  /// Supabase está configurado en esta versión.
  final bool enabled;

  StreamSubscription<sb.AuthState>? _sub;
  bool _googleReady = false;
  bool _devBypass = false;

  sb.GoTrueClient get _auth => sb.Supabase.instance.client.auth;

  sb.User? get user => enabled ? _auth.currentUser : null;

  /// Modo de prueba sin cuenta (solo en desarrollo y sin Supabase).
  bool get canUseDevBypass => kDebugMode && !enabled;

  bool get loggedIn => user != null || _devBypass;

  bool get googleAvailable => enabled && AppConfig.googleEnabled;

  String get providerLabel {
    if (user != null) return 'Google';
    return _devBypass ? 'Modo de prueba' : '';
  }

  String get accountLabel => user?.email ?? '';

  /// Nombre que trae la cuenta de Google, si lo hay.
  String? get suggestedName {
    final m = user?.userMetadata ?? const {};
    for (final k in ['full_name', 'name', 'given_name']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  Future<void> init() async {
    _devBypass = canUseDevBypass && await repo.getSetting('dev_bypass') == '1';
    if (enabled) {
      _sub = _auth.onAuthStateChange.listen((_) => notifyListeners());
    }
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    try {
      if (!googleAvailable) {
        throw const LoginException(
          'El inicio con Google aún no está configurado en esta versión.',
        );
      }
      final google = GoogleSignIn.instance;
      if (!_googleReady) {
        await google.initialize(
          serverClientId: AppConfig.googleWebClientId,
          clientId: AppConfig.googleIosClientId.isEmpty
              ? null
              : AppConfig.googleIosClientId,
        );
        _googleReady = true;
      }
      final GoogleSignInAccount account;
      try {
        account = await google.authenticate(scopeHint: const ['email']);
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          throw const LoginCanceled();
        }
        rethrow;
      }
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const LoginException('Google no devolvió la identificación.');
      }
      await _auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
      );
      final name = suggestedName;
      if (repo.myName.isEmpty && name != null) await repo.setMyName(name);
      notifyListeners();
    } on LoginCanceled {
      rethrow;
    } on LoginException {
      rethrow;
    } on sb.AuthException catch (e) {
      debugPrint('Inicio de sesión: ${e.message}');
      throw LoginException(
        e.message.toLowerCase().contains('provider is not enabled')
            ? 'El inicio con Google no está activado en Supabase.'
            : 'No se pudo iniciar sesión. Intenta de nuevo.',
      );
    } on SocketException {
      throw const LoginException(
        'Sin conexión a internet. Revisa tu señal e intenta de nuevo.',
      );
    } catch (e) {
      debugPrint('Inicio de sesión: $e');
      throw const LoginException(
        'No se pudo iniciar sesión. Intenta de nuevo.',
      );
    }
  }

  Future<void> continueWithoutAccount() async {
    if (!canUseDevBypass) return;
    _devBypass = true;
    await repo.setSetting('dev_bypass', '1');
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_devBypass) {
      _devBypass = false;
      await repo.setSetting('dev_bypass', null);
    }
    if (enabled && _auth.currentUser != null) {
      if (_googleReady) await GoogleSignIn.instance.signOut();
      await _auth.signOut();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
