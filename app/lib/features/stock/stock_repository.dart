import 'package:medstation_core/medstation_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';

class StockAlerts {
  StockAlerts(Map<String, dynamic> r)
      : expiring = [
          for (final e in r['expiring'] as List)
            (StockItem.fromJson(e['item'] as Map<String, dynamic>), StockBatch.fromJson(e['batch'] as Map<String, dynamic>), e['daysLeft'] as int),
        ],
        critical = [for (final e in r['critical'] as List) StockItem.fromJson(e as Map<String, dynamic>)],
        outOfStock = [
          for (final e in r['outOfStock'] as List)
            (
              StockItem.fromJson(e['item'] as Map<String, dynamic>),
              [for (final a in e['alternatives'] as List) (Drug.fromJson(a['drug'] as Map<String, dynamic>), a['inStock'] as int)],
            ),
        ];

  final List<(StockItem, StockBatch, int)> expiring;
  final List<StockItem> critical;
  final List<(StockItem, List<(Drug, int)>)> outOfStock;
}

enum StockDirection {
  giris('Giriş'),
  cikis('Çıkış');

  const StockDirection(this.label);
  final String label;
}

class ScanMovement {
  ScanMovement(this.item, this.batch, this.direction);
  final StockItem item;
  final StockBatch? batch;
  final StockDirection direction;
}

class StockMovement {
  StockMovement(Map<String, dynamic> j)
      : direction = j['direction'] as String,
        quantity = j['quantity'] as int,
        lot = j['lot'] as String?,
        serial = j['serial'] as String?,
        expiry = j['expiry'] == null ? null : DateTime.parse(j['expiry'] as String),
        note = j['note'] as String?,
        at = DateTime.parse(j['at'] as String),
        drugId = j['drugId'] as String,
        drugName = j['drugName'] as String,
        userName = j['userName'] as String;

  final String direction;
  final int quantity;
  final String? lot;
  final String? serial;
  final DateTime? expiry;
  final String? note;
  final DateTime at;
  final String drugId;
  final String drugName;
  final String userName;

  String get label => switch (direction) { 'giris' => 'Giriş', 'cikis' => 'Çıkış', _ => 'Düzeltme' };
}

class StockRepository {
  StockRepository(this.api);
  final ApiClient api;

  Future<List<StockItem>> list() async =>
      [for (final e in (await api.get('/stock'))['items'] as List) StockItem.fromJson(e as Map<String, dynamic>)];

  Future<StockAlerts> alerts({int days = 90}) async => StockAlerts(await api.get('/stock/alerts', query: {'days': days}));

  Future<StockItem> addItem(String drugId, int criticalLevel) async =>
      StockItem.fromJson(await api.post('/stock/items', {'drugId': drugId, 'criticalLevel': criticalLevel}));

  Future<StockItem> addBatch(String itemId, {String? lot, DateTime? expiry, required int quantity}) async =>
      StockItem.fromJson(await api.post('/stock/items/$itemId/batches', {
        'lot': lot,
        'expiry': expiry?.toIso8601String().substring(0, 10),
        'quantity': quantity,
      }));

  /// Karekod/barcode movement. [direction] is giris (receive) or cikis
  /// (dispense); a serial-numbered karekod always moves one pack.
  Future<ScanMovement> scan(String raw, StockDirection direction, {int quantity = 1}) async {
    final r = await api.post('/stock/scan', {'raw': raw, 'direction': direction.name, 'quantity': quantity});
    return ScanMovement(
      StockItem.fromJson(r['item'] as Map<String, dynamic>),
      r['batch'] == null ? null : StockBatch.fromJson(r['batch'] as Map<String, dynamic>),
      direction,
    );
  }

  Future<List<StockMovement>> movements({int limit = 100}) async =>
      [for (final e in (await api.get('/stock/movements', query: {'limit': limit}))['items'] as List) StockMovement(e as Map<String, dynamic>)];

  Future<void> setQuantity(String batchId, int q, {String? note}) =>
      api.send('PATCH', '/stock/batches/$batchId', {'quantity': q, 'note': note});
  Future<void> deleteItem(String id) => api.send('DELETE', '/stock/items/$id');
}

final stockRepositoryProvider = Provider((ref) => StockRepository(ref.watch(apiProvider)));
final stockListProvider = FutureProvider.autoDispose((ref) => ref.watch(stockRepositoryProvider).list());
final stockAlertsProvider = FutureProvider.autoDispose((ref) => ref.watch(stockRepositoryProvider).alerts());
final stockMovementsProvider = FutureProvider.autoDispose((ref) => ref.watch(stockRepositoryProvider).movements());
