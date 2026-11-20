import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recuerditos/sync/couple_crypto.dart';

void main() {
  group('código de invitación', () {
    test('se lee sin importar mayúsculas, guiones o espacios', () {
      final code = InviteCode.generate();
      expect(code.value, hasLength(InviteCode.length));
      final typed = ' ${code.display.toLowerCase().replaceAll('-', ' ')} ';
      expect(InviteCode.tryParse(typed)!.value, code.value);
      expect(code.display, matches(RegExp(r'^\w{3}-\w{3}-\w{3}$')));
    });

    test('rechaza letras confusas y largos equivocados', () {
      expect(InviteCode.tryParse('K7M-2QX-9T'), isNull); // 8
      expect(InviteCode.tryParse('K7M-2QX-9TBB'), isNull); // 10
      expect(InviteCode.tryParse('O7M-2QX-9TB'), isNull); // O
      expect(InviteCode.tryParse('K7M-1QX-9TB'), isNull); // 1
      expect(InviteCode.tryParse('K7M-2QX-9TI'), isNull); // I
      expect(InviteCode.tryParse(''), isNull);
      expect(InviteCode.tryParse('K7M-2QX-9TB'), isNotNull);
    });

    test('solo el mismo código abre el secreto', () async {
      final secret = PairSecret.generate();
      final code = InviteCode.generate();
      final sealed = await code.seal(secret);

      final reopened = await InviteCode.tryParse(code.display)!.open(sealed);
      expect(reopened!.bytes, secret.bytes);

      var other = InviteCode.generate();
      while (other.value == code.value) {
        other = InviteCode.generate();
      }
      expect(await other.open(sealed), isNull);
    });

    test('un paquete dañado o falso no rompe la app', () async {
      final code = InviteCode.generate();
      expect(await code.open('no es base64 !!'), isNull);
      expect(await code.open(base64.encode([1, 2, 3])), isNull);
      expect(await code.open(base64.encode(List.filled(60, 7))), isNull);
    });

    test(
      'el identificador del servidor es estable y no es un hash rápido',
      () async {
        final code = InviteCode.tryParse('K7M2QX9TB')!;
        final again = InviteCode.tryParse('k7m-2qx-9tb')!;
        final id = await code.lookupHash();
        expect(id, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(await again.lookupHash(), id);
        expect(await InviteCode.tryParse('K7M2QX9TC')!.lookupHash(), isNot(id));

        // La versión anterior usaba SHA-256 directo: se podía probar todos los
        // códigos muy rápido a partir de lo guardado en el servidor.
        final fast = await Sha256().hash(
          utf8.encode('recuerditos-invitacion:${code.value}'),
        );
        final fastHex = fast.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        expect(id, isNot(fastHex));
      },
    );
  });

  group('cifrado del buzón', () {
    test('el mismo texto cifrado dos veces se ve distinto', () async {
      final c = await CoupleCrypto.fromSecret(PairSecret.generate());
      final a = await c.encryptText('hola');
      final b = await c.encryptText('hola');
      expect(a, isNot(b));
      expect(await c.decryptText(a), 'hola');
    });

    test('un dato alterado se detecta', () async {
      final c = await CoupleCrypto.fromSecret(PairSecret.generate());
      final data = await c.encrypt(utf8.encode('recuerdo'));
      data[data.length ~/ 2] ^= 1;
      await expectLater(
        c.decrypt(data),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('el id del buzón no revela la llave', () async {
      final secret = PairSecret.generate();
      final c = await CoupleCrypto.fromSecret(secret);
      expect(c.coupleId, isNot(contains(base64Url.encode(secret.bytes))));
      final again = await CoupleCrypto.fromSecret(secret);
      expect(again.coupleId, c.coupleId);
    });

    test(
      'archivos grandes se cifran en otro hilo y siguen siendo compatibles',
      () async {
        final c = await CoupleCrypto.fromSecret(PairSecret.generate());
        final big = List<int>.generate(300 * 1024, (i) => i % 251);
        final sealed = await c.encrypt(big);
        expect(await c.decrypt(sealed), big);

        sealed[sealed.length - 1] ^= 1;
        await expectLater(
          c.decrypt(sealed),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      },
    );
  });
}
