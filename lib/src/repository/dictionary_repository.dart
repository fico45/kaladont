import 'package:supabase/supabase.dart';

abstract interface class DictionaryRepository {
  Future<String> randomWord();
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
}
