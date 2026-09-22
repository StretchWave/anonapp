import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/conversation_repository.dart';
import '../../domain/models/conversation.dart';

/// Provides the [ConversationRepository].
final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ConversationRepository(client);
});

/// Set of conversation IDs that have been marked read locally.
/// This allows instantaneous, 0ms clearing of unread badges in the chats section
/// without waiting for a database roundtrip.
final locallyReadConversationIdsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// Set of conversation IDs that have been deleted client-sided in the active session.
/// Provides instantaneous 0ms removal from the UI while persistent storage commits.
final locallyDeletedConversationIdsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// Provides the list of conversations for the current user.
/// Call `ref.invalidate(conversationsProvider)` to refresh.
final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  final repo = ref.watch(conversationRepositoryProvider);
  final locallyDeleted = ref.watch(locallyDeletedConversationIdsProvider);
  final convs = await repo.getConversations();
  if (locallyDeleted.isEmpty) return convs;
  return convs.where((c) => !locallyDeleted.contains(c.id)).toList();
});
