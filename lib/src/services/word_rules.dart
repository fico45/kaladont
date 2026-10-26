final _wordPattern = RegExp(r'^[a-zčćđšž]+$');
final _letterPattern = RegExp(r'dž|lj|nj|.', unicode: true);

String normalizeWord(String word) => word.trim().toLowerCase();

List<String> croatianLetters(String word) => _letterPattern
    .allMatches(normalizeWord(word))
    .map((m) => m.group(0)!)
    .toList();

bool isPlayableWord(String word) =>
    _wordPattern.hasMatch(word) && croatianLetters(word).length >= 2;

String firstTwoLetters(String word) {
  final letters = croatianLetters(word);
  if (letters.length < 2) {
    throw ArgumentError.value(word, 'word', 'Needs two letters');
  }
  return letters.take(2).join();
}

String lastTwoLetters(String word) {
  final letters = croatianLetters(word);
  if (letters.length < 2) {
    throw ArgumentError.value(word, 'word', 'Needs two letters');
  }
  return letters.skip(letters.length - 2).join();
}
