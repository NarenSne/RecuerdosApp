import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:recuerditos/data/milestones.dart';
import 'package:recuerditos/models/memory.dart';
import 'package:recuerditos/ui/instagram_post_screen.dart';

void main() {
  final start = DateTime(2025, 8, 31);

  test('el mes cae el mismo día, o el último si el mes es más corto', () {
    expect(monthiversary(start, 1), DateTime(2025, 9, 30));
    expect(monthiversary(start, 2), DateTime(2025, 10, 31));
    expect(monthiversary(start, 6), DateTime(2026, 2, 28));
    expect(monthiversary(start, 12), DateTime(2026, 8, 31));
    expect(monthiversary(DateTime(2023, 2, 29 - 1), 12), DateTime(2024, 2, 28));
  });

  test('reconoce meses y aniversarios', () {
    expect(milestoneOn(start, DateTime(2025, 8, 31)), isNull);
    expect(milestoneOn(start, DateTime(2025, 9, 30))!.label, 'Cumplen 1 mes');
    expect(milestoneOn(start, DateTime(2026, 2, 28))!.label, 'Cumplen 6 meses');
    expect(milestoneOn(start, DateTime(2026, 2, 27)), isNull);
    final aniv = milestoneOn(start, DateTime(2026, 8, 31))!;
    expect(aniv.isAnniversary, isTrue);
    expect(aniv.label, 'Cumplen 1 año');
    expect(milestoneOn(start, DateTime(2027, 8, 31))!.label, 'Cumplen 2 años');
  });

  test('próximo mes y tiempo juntos', () {
    final s = DateTime(2025, 8, 3);
    expect(
      nextMilestone(s, DateTime(2026, 11, 19)).date,
      DateTime(2026, 12, 3),
    );
    expect(nextMilestone(s, DateTime(2026, 12, 3)).months, 16);
    expect(nextMilestone(s, DateTime(2025, 8, 3)).months, 1);
    expect(timeTogether(s, DateTime(2026, 11, 19)), '1 año y 3 meses');
    expect(timeTogether(s, DateTime(2026, 11, 2)), '1 año y 2 meses');
    expect(timeTogether(s, DateTime(2026, 8, 3)), '1 año');
    expect(timeTogether(s, DateTime(2025, 8, 10)), '7 días');
  });

  test('el post empieza con una foto como portada', () {
    MediaItem item(String id, String type) => MediaItem(
      id: id,
      memoryId: 'm',
      type: type,
      ext: 'x',
      position: 0,
      updatedAt: 0,
    );
    final v1 = item('v1', 'video'), p1 = item('p1', 'photo');
    final p2 = item('p2', 'photo'), v2 = item('v2', 'video');
    expect(arrangeForInstagram([v1, p1, v2, p2]), [p1, v1, v2, p2]);
    expect(arrangeForInstagram([v1, v2]), [v1, v2]);
  });

  test('las fotos se recortan a 4:5 de 1080 x 1350', () async {
    final dir = Directory.systemTemp.createTempSync('ig');
    final src = '${dir.path}/a.jpg';
    File(
      src,
    ).writeAsBytesSync(img.encodeJpg(img.Image(width: 3000, height: 2000)));
    final out = '${dir.path}/b.jpg';
    await cropTo4x5InBackground(src, out);
    final result = img.decodeJpg(File(out).readAsBytesSync())!;
    expect((result.width, result.height), (1080, 1350));
    dir.deleteSync(recursive: true);
  });
}
