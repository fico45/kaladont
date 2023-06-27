import 'dart:math';

import '../consts.dart';

class Formatter {
  static String getRandomString(int length) =>
      String.fromCharCodes(Iterable.generate(
          length,
          (_) => Globals.chars
              .codeUnitAt(Random().nextInt(Globals.chars.length))));
}
