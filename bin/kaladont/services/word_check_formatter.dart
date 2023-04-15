class WordCheckFormatter {
  static String getFirstTwoLetters({required String word}) {
    String wordToCheck = word.toLowerCase();
    String substring = wordToCheck.substring(0, 3);
    bool containsNJ = substring.contains('nj');
    return containsNJ ? substring : wordToCheck.substring(0, 2);
  }

  static String getLastTwoLetters({required String word, required int length}) {
    String wordToCheck = word.toLowerCase();
    String substring = wordToCheck.substring(length - 2, length + 1);
    bool containsNJ = substring.contains('nj');
    return containsNJ
        ? substring
        : wordToCheck.substring(length - 1, length + 1);
  }
}
