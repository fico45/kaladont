class WordCheckFormatter {
  static String getFirstTwoLetters({required String word}) {
    return word[0] + word[1];
  }

  static String getLastTwoLetters({required String word, required int length}) {
    return word[length - 1] + word[length];
  }
}
