class WordCheckFormatter {
  static String getFirstTwoLetters({required String word}) {
    String wordToCheck = word.toLowerCase();
    String substring = wordToCheck.substring(0, 3);
    bool hasLast3Letters = containsLast3Letters(substring: substring);
    return hasLast3Letters ? substring : wordToCheck.substring(0, 2);
  }

  static String getLastTwoLetters({required String word, required int length}) {
    String wordToCheck = word.toLowerCase();
    String substring = wordToCheck.substring(length - 2, length + 1);
    bool hasLast3Letters = containsLast3Letters(substring: substring);
    return hasLast3Letters
        ? substring
        : wordToCheck.substring(length - 1, length + 1);
  }

  static bool containsLast3Letters({required String substring}) {
    bool contains = false;
    if (substring.contains('nj')) {
      contains = true;
    } else if (substring.contains('lj')) {
      contains = true;
    } else if (substring.contains('dž')) {
      contains = true;
    }
    return contains;
  }
}
