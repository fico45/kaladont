import 'package:discord_bot/src/services/word_rules.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes whitespace and Croatian uppercase', () {
    expect(normalizeWord('  ČAŠA  '), 'čaša');
  });
  test('short and non-word inputs are safe', () {
    for (final word in ['', 'a', 'nj', 'lj', 'dž', 'two words', 'hi!', '123']) {
      expect(isPlayableWord(word), isFalse, reason: word);
    }
    expect(isPlayableWord('on'), isTrue);
    expect(firstTwoLetters('on'), 'on');
    expect(lastTwoLetters('on'), 'on');
    expect(() => firstTwoLetters('a'), throwsArgumentError);
    expect(() => lastTwoLetters('nj'), throwsArgumentError);
  });
  test('counts digraphs as letters, including adjacent digraphs', () {
    expect(firstTwoLetters('ljnjiva'), 'ljnj');
    expect(lastTwoLetters('ljnj'), 'ljnj');
    expect(firstTwoLetters('njiva'), 'nji');
    expect(lastTwoLetters('konj'), 'onj');
    expect(firstTwoLetters('džep'), 'dže');
    expect(() => lastTwoLetters('dž'), throwsArgumentError);
  });
}
