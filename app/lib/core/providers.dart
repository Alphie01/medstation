import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'env.dart';
import 'network/api_client.dart';
import 'storage/session_store.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// Overridden in main() after SharedPreferences loads. Holds only
/// non-sensitive preferences (recent ingredient searches, settings).
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

/// Called by the API client when a refresh fails; wired to auth in main.
final sessionExpiredProvider = Provider<void Function()>((ref) => () {});

final apiProvider = Provider<ApiClient>((ref) => ApiClient(
      baseUrl: Env.apiBase,
      store: ref.watch(sessionStoreProvider),
      onSessionExpired: () => ref.read(sessionExpiredProvider)(),
    ));

/// Data source status: which datasets are connected, versions and dates.
class Meta {
  Meta(this.raw);
  final Map<String, dynamic> raw;

  List<Map<String, dynamic>> get sources => (raw['sources'] as List).cast();
  bool get interactionDbConnected => raw['interactionDbConnected'] as bool;
  bool get medulaAvailable => raw['medulaAvailable'] as bool;
  bool get assistantAvailable => raw['assistantAvailable'] as bool;
  bool get anySample => sources.any((s) => s['isSample'] == true);

  Map<String, dynamic>? source(String kind) =>
      sources.where((s) => (s['kind'] as String).startsWith(kind)).firstOrNull;
}

final metaProvider = FutureProvider<Meta>((ref) async => Meta(await ref.watch(apiProvider).get('/meta/provenance')));
