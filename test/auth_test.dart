import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:recuerditos/data/auth.dart';
import 'package:recuerditos/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Repository repo;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('auth');
    final db = await Repository.openDb(
      p.join(root.path, 'db.sqlite'),
      factory: databaseFactoryFfi,
    );
    repo = Repository(db, root);
    await repo.init();
  });

  tearDown(() async {
    await repo.close();
    root.deleteSync(recursive: true);
  });

  test('sin Supabase no hay sesión, salvo el modo de prueba', () async {
    final auth = AuthService(repo: repo, enabled: false);
    await auth.init();
    expect(auth.loggedIn, isFalse);
    expect(auth.googleAvailable, isFalse);
    await expectLater(auth.signInWithGoogle(), throwsA(isA<LoginException>()));

    expect(auth.canUseDevBypass, isTrue); // las pruebas corren en modo debug
    await auth.continueWithoutAccount();
    expect(auth.loggedIn, isTrue);

    final reopened = AuthService(repo: repo, enabled: false);
    await reopened.init();
    expect(reopened.loggedIn, isTrue);

    await reopened.signOut();
    expect(reopened.loggedIn, isFalse);
  });

  test('el apodo de la pareja se guarda', () async {
    await repo.setPartnerNickname('  Mi Sol ');
    expect(repo.partnerNickname, 'Mi Sol');
  });
}
