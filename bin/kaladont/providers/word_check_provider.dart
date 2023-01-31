/* //write a repository class for word chceck provider in Dart with Riverpod

import 'package:riverpod/riverpod.dart';

import '../model/word_model.dart';
import '../services/get_random_word.dart';

final wordCheckProvider = Provider<WordCheckProvider>((ref) {
  return WordCheckProvider();
});

final wordProvider = StateNotifierProvider<WordCheckProvider, Word>((ref) {
  String word;
  getRandomWord().then((value) => word = value);
  return WordCheckProvider();
});

class WordCheckProvider extends StateNotifier<Word> {
  WordCheckProvider()
      : super(Word(
            currentWord: '',
            lastGuess: false,
            previousExistsInDictionary: false,
            previousWord: '',
            victory: false));

  void setWord({required String wordToCheck}) {
    state = state.copyWith(currentWord: wordToCheck);
  }

  void setPreviousWord({required String previousWord}) {
    state = state.copyWith(previousWord: previousWord);
  }

  void setLastGuess({required bool lastGuess}) {
    state = state.copyWith(lastGuess: lastGuess);
  }

  void setVictory({required bool victory}) {
    state = state.copyWith(victory: victory);
  }

  void setPreviousExistsInDictionary(
      {required bool previousExistsInDictionary}) {
    state =
        state.copyWith(previousExistsInDictionary: previousExistsInDictionary);
  }
}
 */