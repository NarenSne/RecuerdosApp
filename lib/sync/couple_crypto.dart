import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// El código que una persona le pasa a su pareja para conectarse.
///
/// Contiene 32 bytes aleatorios. De ahí salen dos cosas distintas:
/// - el identificador del buzón (lo único que ve el servidor), y
/// - la llave de cifrado (nunca sale del teléfono).
class PairSecret {
  PairSecret(this.bytes);

  static const prefix = 'RCD1-';
  final List<int> bytes;

  factory PairSecret.generate() {
    final rnd = Random.secure();
    return PairSecret(List<int>.generate(32, (_) => rnd.nextInt(256)));
  }

  String encode() => prefix + base64Url.encode(bytes).replaceAll('=', '');

  static PairSecret? tryParse(String input) {
    final s = input.replaceAll(RegExp(r'\s'), '');
    if (!s.startsWith(prefix)) return null;
    final body = s.substring(prefix.length);
    try {
      final bytes = base64Url.decode(base64Url.normalize(body));
      return bytes.length == 32 ? PairSecret(bytes) : null;
    } on FormatException {
      return null;
    }
  }
}

/// Desde este tamaño el cifrado se hace en otro hilo (isolate): una foto o un
/// video tardan de cientos de milisegundos a varios segundos y la pantalla
/// se congelaría mientras tanto.
const _backgroundThreshold = 64 * 1024;

final _aes = AesGcm.with256bits();

// Funciones de nivel superior: Isolate.run solo puede copiar datos simples,
// no objetos como CoupleCrypto.
Future<Uint8List> _encryptWith(List<int> key, List<int> plain) async {
  final box = await _aes.encrypt(plain, secretKey: SecretKey(key));
  return Uint8List.fromList(box.concatenation());
}

Future<List<int>> _decryptWith(List<int> key, List<int> data) {
  final box = SecretBox.fromConcatenation(
    data,
    nonceLength: _aes.nonceLength,
    macLength: _aes.macAlgorithm.macLength,
  );
  return _aes.decrypt(box, secretKey: SecretKey(key));
}

/// Cifra y descifra todo lo que pasa por el buzón (AES-256-GCM).
class CoupleCrypto {
  CoupleCrypto._(this.coupleId, this._key);

  final String coupleId;
  final List<int> _key;

  static Future<CoupleCrypto> fromSecret(PairSecret secret) async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(secret.bytes),
      nonce: utf8.encode('recuerditos-v1'),
      info: utf8.encode('cifrado'),
    );
    final hash = await Sha256().hash([
      ...utf8.encode('recuerditos-pareja:'),
      ...secret.bytes,
    ]);
    final id = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return CoupleCrypto._(id, List.unmodifiable(await key.extractBytes()));
  }

  Future<Uint8List> encrypt(List<int> plain) {
    final key = _key;
    if (plain.length < _backgroundThreshold) return _encryptWith(key, plain);
    return Isolate.run(() => _encryptWith(key, plain));
  }

  /// Lanza [SecretBoxAuthenticationError] si el dato fue alterado o se cifró
  /// con otra llave.
  Future<List<int>> decrypt(List<int> data) {
    final key = _key;
    if (data.length < _backgroundThreshold) return _decryptWith(key, data);
    return Isolate.run(() => _decryptWith(key, data));
  }

  Future<String> encryptText(String text) async =>
      base64.encode(await encrypt(utf8.encode(text)));

  Future<String> decryptText(String data) async =>
      utf8.decode(await decrypt(base64.decode(data)));
}

/// Código corto y temporal para invitar a la pareja (ej. K7M-2QX-9TB).
///
/// El servidor guarda el secreto de la pareja cifrado con una llave que sale
/// de este código, y solo lo entrega una vez, antes de que venza. El servidor
/// identifica la invitación por un identificador que también sale del código.
///
/// Llave e identificador salen de una sola derivación lenta (PBKDF2): quien
/// vea el identificador en el servidor no puede probar códigos a gran
/// velocidad para descubrir el código y abrir el secreto.
class InviteCode {
  InviteCode._(this.value);

  /// Sin 0/O, 1/I/L para que no se confundan al dictarlo o escribirlo.
  static const _alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const length = 9;
  static const validFor = Duration(minutes: 15);

  /// Solo letras y números, en mayúsculas.
  final String value;

  factory InviteCode.generate() {
    final rnd = Random.secure();
    return InviteCode._(
      List.generate(
        length,
        (_) => _alphabet[rnd.nextInt(_alphabet.length)],
      ).join(),
    );
  }

  static InviteCode? tryParse(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.length != length) return null;
    for (final c in s.split('')) {
      if (!_alphabet.contains(c)) return null;
    }
    return InviteCode._(s);
  }

  /// K7M-2QX-9TB
  String get display =>
      '${value.substring(0, 3)}-${value.substring(3, 6)}-${value.substring(6)}';

  /// 64 bytes: los primeros 32 son la llave, los otros 32 el identificador.
  /// Tarda alrededor de un segundo, así que se calcula en otro hilo.
  late final Future<List<int>> _derived = _deriveInBackground(value);

  // Estática para que el otro hilo reciba solo el texto del código y no
  // este objeto.
  static Future<List<int>> _deriveInBackground(String code) =>
      Isolate.run(() => _deriveInvite(code));

  /// Identificador de la invitación en el servidor (64 caracteres hex).
  Future<String> lookupHash() async {
    final bytes = (await _derived).sublist(32);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<SecretKey> _key() async => SecretKey((await _derived).sublist(0, 32));

  Future<String> seal(PairSecret secret) async {
    final box = await AesGcm.with256bits().encrypt(
      secret.bytes,
      secretKey: await _key(),
    );
    return base64.encode(box.concatenation());
  }

  /// Null si el paquete no corresponde a este código.
  Future<PairSecret?> open(String sealed) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64.decode(sealed),
        nonceLength: 12,
        macLength: 16,
      );
      final bytes = await AesGcm.with256bits().decrypt(
        box,
        secretKey: await _key(),
      );
      return bytes.length == 32 ? PairSecret(bytes) : null;
    } on SecretBoxAuthenticationError {
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      // Paquete demasiado corto para ser una invitación.
      return null;
    }
  }
}

Future<List<int>> _deriveInvite(String code) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 60000,
        bits: 512,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(code)),
        nonce: utf8.encode('recuerditos-invitacion-v2'),
      );
  return key.extractBytes();
}
