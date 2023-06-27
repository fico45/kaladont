import 'dart:math';

import 'package:riverpod/riverpod.dart';

import '../client.dart';
import '../formatters.dart';
import '../model/word_model.dart';

final savedWordProvider = StateNotifierProvider<SavedWordProvider, Word>((ref) {
  return SavedWordProvider();
});

class SavedWordProvider extends StateNotifier<Word> {
  SavedWordProvider()
      : super(Word(
            currentWord: "laminat",
            previousWord: "lamela",
            lastGuess: true,
            victory: false,
            previousExistsInDictionary: true,
            possibleAnswers: 0));

  void setWord(Word word) {
    state = word;
  }

  Future<String> getRandomWord() async {
    List randomWord = [];
    int retry = 0;
    String randomCharacter = Formatter.getRandomString(1);
    while (retry < 30) {
      randomWord = await SPC.client
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
    state = Word(
      currentWord: randomWord[randomGeneratedWordIndex]['word'].toLowerCase(),
      previousWord: "",
      lastGuess: true,
      victory: false,
      previousExistsInDictionary: true,
      possibleAnswers: 0,
    );
    return state.currentWord;
  }

  Future<void> loadWord() async {
    try {
      final getWordResponse = await SPC.client.from('words').select();
      Word newWord = Word(
          currentWord: getWordResponse[0]['current_word'],
          previousWord: getWordResponse[0]['previous_word'],
          lastGuess: getWordResponse[0]['last_guess'],
          victory: getWordResponse[0]['victory'],
          previousExistsInDictionary: getWordResponse[0]
              ['previous_exists_in_dictionary'],
          possibleAnswers: getWordResponse[0]['possible_answers']);

      state = newWord;
    } catch (e) {
      print(e);
    }
  }

  /*  Future<void> saveWord() async {
    try {
      final updateWordResponse = await client
          .from('words')
          .update({'current_word': state.currentWord}).eq('id', 1).execute();
    } catch (e) {
      print(e);
    }
  } */
}
