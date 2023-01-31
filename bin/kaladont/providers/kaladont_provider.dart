import 'package:riverpod/riverpod.dart';

import '../model/word_model.dart';

final savedWordProvider = Provider<Word>((ref) {
  return Word(
      currentWord: "laminat",
      previousWord: "lamela",
      lastGuess: true,
      victory: false,
      previousExistsInDictionary: true,
      possibleAnswers: 0);
});
