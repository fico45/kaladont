import 'package:supabase/supabase.dart';

abstract interface class DictionaryRepository {
  Future<String> randomWord();
  Future<bool> contains(String word);
  Future<int> countContinuations(String prefix, Set<String> usedWords);
}

final class EmptyDictionaryException implements Exception {
  const EmptyDictionaryException();
}

final class SupabaseDictionaryRepository implements DictionaryRepository {
  final SupabaseClient client;
  const SupabaseDictionaryRepository(this.client);

  @override
  Future<String> randomWord() async {
    final word = await client.rpc<String?>('kaladont_random_word');
    if (word == null) throw const EmptyDictionaryException();
    return word;
  }

  @override
  Future<bool> contains(String word) async {
    final rows = await client
        .from('words')
        .select('word')
        .ilike('word', word)
        .inFilter('type', ['imenica', 'glagol', 'pridjev'])
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<int> countContinuations(String prefix, Set<String> usedWords) async =>
      await client.rpc<int>(
        'kaladont_count_continuations',
        params: {'p_prefix': prefix, 'p_used_words': usedWords.toList()},
      );
}
