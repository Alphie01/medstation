import 'dart:convert';

import 'package:medstation_core/medstation_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';

class SearchQuery {
  const SearchQuery({this.text, this.ingredients = const [], this.mode = MatchMode.incl, this.form});
  final String? text;
  final List<String> ingredients;
  final MatchMode mode;
  final FormGroup? form;

  String get _key => '${text ?? ''}|${ingredients.join('+')}|${mode.name}|${form?.name}';
  @override
  bool operator ==(Object other) => other is SearchQuery && other._key == _key;
  @override
  int get hashCode => _key.hashCode;

  SearchQuery copyWith({MatchMode? mode, FormGroup? form, bool clearForm = false}) => SearchQuery(
      text: text, ingredients: ingredients, mode: mode ?? this.mode, form: clearForm ? null : form ?? this.form);
}

class SearchResponse {
  SearchResponse(this.items, this.incl, this.exact, this.forms);
  final List<Drug> items;
  final int incl;
  final int exact;
  final Map<String, int> forms;

  bool get anySample => items.any((d) => d.provenance.isSample);
}

class IngredientHit {
  IngredientHit(this.name, this.productCount);
  final String name;
  final int productCount;
}

class SearchRepository {
  SearchRepository(this.api);
  final ApiClient api;

  Future<SearchResponse> search(SearchQuery q) async {
    final r = await api.get('/drugs/search', query: {
      if (q.text != null) 'q': q.text,
      if (q.ingredients.isNotEmpty) 'ingredients': q.ingredients.join(','),
      'mode': q.mode.name,
      if (q.form != null) 'form': q.form!.name,
    });
    final counts = r['counts'] as Map<String, dynamic>;
    return SearchResponse(
      (r['items'] as List).map((e) => Drug.fromJson(e as Map<String, dynamic>)).toList(),
      counts['incl'] as int,
      counts['exact'] as int,
      (r['forms'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
    );
  }

  Future<List<IngredientHit>> suggest(String q) async {
    final r = await api.get('/ingredients/suggest', query: {'q': q});
    return [for (final x in r['items'] as List) IngredientHit(x['name'] as String, x['productCount'] as int)];
  }

  Future<List<IngredientHit>> top() async {
    final r = await api.get('/ingredients/top');
    return [for (final x in r['items'] as List) IngredientHit(x['name'] as String, x['productCount'] as int)];
  }

  Future<Drug> drug(String id) async => Drug.fromJson(await api.get('/drugs/$id'));

  Future<List<Drug>> equivalents(String id) async {
    final r = await api.get('/drugs/$id/equivalents');
    return (r['items'] as List).map((e) => Drug.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Drug>> favorites() async {
    final r = await api.get('/favorites');
    return (r['items'] as List).map((e) => Drug.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setFavorite(String id, bool on) => api.send(on ? 'PUT' : 'DELETE', '/favorites/$id');
}

final searchRepositoryProvider = Provider((ref) => SearchRepository(ref.watch(apiProvider)));

final searchProvider = FutureProvider.autoDispose.family<SearchResponse, SearchQuery>(
    (ref, q) => ref.watch(searchRepositoryProvider).search(q));

final drugProvider = FutureProvider.autoDispose.family<Drug, String>((ref, id) => ref.watch(searchRepositoryProvider).drug(id));

final equivalentsProvider =
    FutureProvider.autoDispose.family<List<Drug>, String>((ref, id) => ref.watch(searchRepositoryProvider).equivalents(id));

final topIngredientsProvider = FutureProvider<List<IngredientHit>>((ref) => ref.watch(searchRepositoryProvider).top());

final favoritesProvider = FutureProvider.autoDispose<List<Drug>>((ref) => ref.watch(searchRepositoryProvider).favorites());

/// Recent ingredient searches, stored on device. Only ingredient names — no
/// patient data — so plain preferences are adequate.
class RecentSearch {
  RecentSearch(this.ingredients, this.at);
  final List<String> ingredients;
  final DateTime at;
}

class RecentSearches extends Notifier<List<RecentSearch>> {
  static const _key = 'recent_searches';
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  List<RecentSearch> build() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final x in jsonDecode(raw) as List)
          RecentSearch((x['i'] as List).cast<String>(), DateTime.parse(x['t'] as String)),
      ];
    } catch (_) {
      return const [];
    }
  }

  void add(List<String> ingredients) {
    if (ingredients.isEmpty) return;
    final key = ingredients.join('+');
    final next = [
      RecentSearch(List.of(ingredients), DateTime.now()),
      ...state.where((r) => r.ingredients.join('+') != key),
    ].take(8).toList();
    state = next;
    _prefs.setString(_key, jsonEncode([for (final r in next) {'i': r.ingredients, 't': r.at.toIso8601String()}]));
  }

  /// Ingredients ranked by how often this pharmacist searched them.
  List<String> frequent() {
    final n = <String, int>{};
    for (final r in state) {
      for (final i in r.ingredients) {
        n[i] = (n[i] ?? 0) + 1;
      }
    }
    return (n.keys.toList()..sort((a, b) => n[b]!.compareTo(n[a]!)));
  }

  void clear() {
    state = const [];
    _prefs.remove(_key);
  }
}

final recentSearchesProvider = NotifierProvider<RecentSearches, List<RecentSearch>>(RecentSearches.new);
