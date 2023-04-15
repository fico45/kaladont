import 'dart:math';

import '../../main.dart';

Future<String> getRandomWord() async {
  List randomWord = [];
  int retry = 0;
  String randomCharacter = getRandomString(1);
  while (retry < 30) {
    randomWord = await client
        .from('words')
        .select('word')
        .filter('type', 'in', '("imenica", "glagol")')
        .like('word', '%$randomCharacter%');
    if (randomWord.isNotEmpty) {
      break;
    }
  }
  int randomGeneratedWordIndex = Random().nextInt(randomWord.length);
  print(randomWord.length);

  return randomWord[randomGeneratedWordIndex]['word'];
}

const _chars = 'AaBbCcĆćČčDdĐđEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsŠšTtUuVvZzŽž';
Random _rnd = Random();
String getRandomString(int length) => String.fromCharCodes(Iterable.generate(
    length, (_) => _chars.codeUnitAt(_rnd.nextInt(_chars.length))));
