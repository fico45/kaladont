import 'package:supabase/supabase.dart';

import '../../main.dart';
import '../model/word_model.dart';

String getFirstTwoLetters({required String word}) {
  return word[0] + word[1];
}

String getLastTwoLetters({required String word, required int length}) {
  return word[length - 1] + word[length];
}

Future<Word> checkWord(
    {required Word savedWord, required String wordToCheck}) async {
  int wordLength = savedWord.currentWord.length - 1;
  String newWordFirstLetters = getFirstTwoLetters(word: wordToCheck);
  String oldWordLastLetters =
      getLastTwoLetters(word: savedWord.currentWord, length: wordLength);
  if (oldWordLastLetters == newWordFirstLetters) {
    print("Riječ je validna");
    bool isValid = await validateWord(wordToCheck: wordToCheck);
    if (!isValid) {
      savedWord.setPreviousExistsInDictionary(false);
      return savedWord;
    } else {
      bool isWin = await checkForWin(word: wordToCheck);
      return Word(
        currentWord: wordToCheck,
        lastGuess: true,
        previousWord: savedWord.currentWord,
        victory: isWin,
        previousExistsInDictionary: true,
      );
    }
  } else {
    savedWord.setLastGuess(false);
    return savedWord;
  }
}

Future<bool> validateWord({required String wordToCheck}) async {
  List response;

  try {
    response = await client
        .from('words')
        .select()
        .eq('word', wordToCheck)
        .filter('type', 'in', '("imenica", "glagol")');
  } catch (e) {
    response = [];
    print(e);
  }
  if (response.isEmpty) {
    print('Riječ ne postoji u riječniku. :(');
    return false;
  } else {
    print('Riječ postoji u riječniku!');
    return true;
  }
}

Future<bool> checkForWin({required String word}) async {
  String lastTwoLetters =
      getLastTwoLetters(word: word, length: word.length - 1);
  List response = await client
      .from('words')
      .select()
      .like('word', '$lastTwoLetters%')
      .filter('type', 'in', '("imenica", "glagol")');

  if (response.isEmpty) {
    print('Riječi koje počinju na $lastTwoLetters ne postoje u rječniku');
    return true;
  } else {
    print(
        'Riječi koje počinju na $lastTwoLetters postoje u rječniku. Njih je ${response.length}');
    return false;
  }
}