class Word {
  final String currentWord;
  bool lastGuess;
  final String previousWord;
  bool victory;
  bool previousExistsInDictionary;
  int possibleAnswers;

  Word(
      {required this.currentWord,
      required this.lastGuess,
      required this.previousWord,
      required this.victory,
      required this.previousExistsInDictionary,
      required this.possibleAnswers});

  void setLastGuess(bool newLastGuess) {
    lastGuess = newLastGuess;
  }

  void setPreviousExistsInDictionary(bool newPreviousExistsInDictionary) {
    previousExistsInDictionary = newPreviousExistsInDictionary;
  }
}
