import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/conversation_repository.dart';
import '../../domain/models/conversation.dart';

/// Provides the [ConversationRepository].
final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ConversationRepository(client);
});

/// Provides the list of conversations for the current user.
/// Call `ref.invalidate(conversationsProvider)` to refresh.
final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  final repo = ref.watch(conversationRepositoryProvider);
  return repo.getConversations();
});
