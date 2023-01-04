import 'dart:math';

import '../../main.dart';

Future<String> getRandomWord() async {
  List randomWord = [];
  int retry = 0;

  while (retry < 30) {
    randomWord = await client
        .from('words')
        .select('word')
        .filter('type', 'in', '("imenica", "glagol")');
    if (randomWord.isNotEmpty) {
      break;
    }
  }
  int random = randomWord.length;
  int randomGeneratedWordIndex = Random().nextInt(randomWord.length);
  return randomWord[randomGeneratedWordIndex];
}
