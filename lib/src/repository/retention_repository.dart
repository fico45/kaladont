import 'package:supabase/supabase.dart';

final class SupabaseRetentionRepository {
  final SupabaseClient client;
  const SupabaseRetentionRepository(this.client);

  Future<int> pruneBatch() => client.rpc<int>(
    'kaladont_prune_receipts',
    params: {'p_batch_size': 1000},
  );
}
