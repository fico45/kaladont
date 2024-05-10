import '../../consts.dart';
import '../model/word_model.dart';
import '../repository/client_repository.dart';
import 'word_check_formatter.dart';

Future<Word> checkWord({
  required Word savedWord,
  required String wordToCheck,
}) async {
  bool isValid = await validateWord(wordToCheck: wordToCheck);
  if (!isValid) {
    savedWord.setPreviousExistsInDictionary(false);
    return savedWord;
  } else {
    int possibleAnswers = await checkForWin(word: wordToCheck);
    bool isWin = possibleAnswers == 0;
    return Word(
        currentWord: wordToCheck,
        lastGuess: true,
        previousWord: savedWord.currentWord,
        victory: isWin,
        previousExistsInDictionary: true,
        possibleAnswers: possibleAnswers);
  }
}

Future<bool> validateWord({required String wordToCheck}) async {
  List response;

  try {
    response = await SPC.client
        .from('words')
        .select()
        .ilike('word', wordToCheck.toLowerCase())
        .filter('type', 'in', Globals.supabaseFilter);
    print("Ovoliko riječi je u bazi: ${response.length}");
  } catch (e) {
    response = [];
    print(e);
  }
  if (response.isEmpty) {
//word does not exist in DB
    return false;
  } else {
//word exists in DB
    return true;
  }
}

Future<int> checkForWin({required String word}) async {
  String lastTwoLetters =
      WordCheckFormatter.getLastTwoLetters(word: word, length: word.length - 1);
  List response = await SPC.client
      .from('words')
      .select()
      .like('word', '$lastTwoLetters%')
      .filter('type', 'in', Globals.supabaseFilter);

  List allowedWords = [];
  for (var i = 0; i < response.length; i++) {
    if (!Globals.usedWords.contains(response[i]['word'])) {
      allowedWords.add(response[i]['word']);
    }
  }

  if (allowedWords.isEmpty) {
    print('Riječi koje počinju na $lastTwoLetters ne postoje u rječniku');
    return 0;
  } else {
    print(
        'Riječi koje počinju na $lastTwoLetters postoje u rječniku. Njih je ${allowedWords.length}');
    return allowedWords.length;
  }
}
