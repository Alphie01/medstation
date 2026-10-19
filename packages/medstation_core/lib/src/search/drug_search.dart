import '../models/drug.dart';
import '../models/text.dart';

enum MatchMode {
  /// Contains every selected ingredient, possibly more ("içeren ilaç").
  incl,

  /// Contains exactly the selected ingredients ("tam eşdeğer").
  exact,
}

/// Filters [drugs] by selected base ingredients, as in the reference
/// Sonuçlar screen.
List<Drug> matchIngredients(
  Iterable<Drug> drugs,
  Iterable<String> selected,
  MatchMode mode,
) {
  final want = selected.map(baseIngredient).toSet();
  if (want.isEmpty) return const [];
  return drugs.where((d) {
    final have = d.ingredients.map((i) => baseIngredient(i.name)).toSet();
    if (!have.containsAll(want)) return false;
    return mode == MatchMode.incl || have.length == want.length;
  }).toList();
}

class DrugGroup {
  DrugGroup(this.key, this.items);
  final String key;
  final List<Drug> items;
  Drug get representative => items.first;
}

/// Groups drugs that are interchangeable (same ingredients, amounts and form
/// group, or the same TİTCK equivalence code). Largest groups first.
List<DrugGroup> groupEquivalents(Iterable<Drug> drugs) {
  final map = <String, List<Drug>>{};
  for (final d in drugs) {
    map.putIfAbsent(d.equivalenceKey, () => []).add(d);
  }
  final groups = [for (final e in map.entries) DrugGroup(e.key, e.value)];
  groups.sort((a, b) => b.items.length.compareTo(a.items.length));
  return groups;
}

/// Products interchangeable with [drug] from [pool], excluding itself.
List<Drug> equivalentsOf(Drug drug, Iterable<Drug> pool) => pool
    .where((d) => d.id != drug.id && d.equivalenceKey == drug.equivalenceKey)
    .toList();
