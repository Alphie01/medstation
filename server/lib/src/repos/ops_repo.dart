import 'package:medstation_core/medstation_core.dart';
import 'package:postgres/postgres.dart';

import '../auth.dart';
import '../db.dart';
import '../http.dart';
import 'drug_repo.dart';

class StockRepo {
  StockRepo(this.db, this.drugs);
  final Db db;
  final DrugRepo drugs;

  Future<List<StockItem>> list(String pharmacyId, {String? itemId}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT i.id, i.drug_id, d.name || COALESCE(' ' || d.strength, '') AS drug_name,
               d.barcode, i.critical_level, b.id AS bid, b.lot, b.serial, b.expiry, b.quantity
        FROM stock_items i JOIN drugs d ON d.id = i.drug_id
        LEFT JOIN stock_batches b ON b.item_id = i.id
        WHERE i.pharmacy_id = @p ${itemId == null ? '' : 'AND i.id = @i'}
        ORDER BY d.name, b.expiry NULLS LAST'''),
      parameters: {'p': pharmacyId, 'i': ?itemId},
    );
    final items = <String, Map<String, dynamic>>{};
    for (final row in r) {
      final m = row.toColumnMap();
      final it = items.putIfAbsent(m['id'] as String, () => {...m, 'batches': <StockBatch>[]});
      if (m['bid'] != null) {
        (it['batches'] as List<StockBatch>).add(StockBatch(
          id: m['bid'] as String,
          lot: m['lot'] as String?,
          serial: m['serial'] as String?,
          expiry: m['expiry'] as DateTime?,
          quantity: m['quantity'] as int,
        ));
      }
    }
    return [
      for (final m in items.values)
        StockItem(
          id: m['id'] as String,
          drugId: m['drug_id'] as String,
          drugName: m['drug_name'] as String,
          barcode: m['barcode'] as String?,
          criticalLevel: m['critical_level'] as int,
          batches: m['batches'] as List<StockBatch>,
        ),
    ];
  }

  Future<StockItem> upsertItem(String pharmacyId, String drugId, int criticalLevel) async {
    if (criticalLevel < 0) throw ApiError.badRequest('Kritik seviye negatif olamaz');
    if (await drugs.byId(drugId) == null) throw ApiError.notFound('İlaç bulunamadı');
    final r = await db.execute(
      Sql.named('''
        INSERT INTO stock_items (id, pharmacy_id, drug_id, critical_level) VALUES (@id, @p, @d, @c)
        ON CONFLICT (pharmacy_id, drug_id) DO UPDATE SET critical_level = EXCLUDED.critical_level
        RETURNING id'''),
      parameters: {'id': newId(), 'p': pharmacyId, 'd': drugId, 'c': criticalLevel},
    );
    return (await list(pharmacyId, itemId: r.first[0] as String)).single;
  }

  Future<void> _ownItem(String pharmacyId, String itemId) async {
    final r = await db.execute(
        Sql.named('SELECT 1 FROM stock_items WHERE id = @i AND pharmacy_id = @p'),
        parameters: {'i': itemId, 'p': pharmacyId});
    if (r.isEmpty) throw ApiError.notFound('Stok kalemi bulunamadı');
  }

  Future<String> _drugOf(String itemId) async =>
      (await db.execute(Sql.named('SELECT drug_id FROM stock_items WHERE id = @i'), parameters: {'i': itemId}))
          .first[0] as String;

  Future<void> _move(TxSession s, {
    required String pharmacyId,
    required String userId,
    required String itemId,
    required String drugId,
    required String direction,
    required int quantity,
    String? lot,
    String? serial,
    DateTime? expiry,
    String? note,
  }) =>
      s.execute(
        Sql.named('INSERT INTO stock_movements (id, pharmacy_id, item_id, drug_id, user_id, direction, quantity, '
            'lot, serial, expiry, note) VALUES (@id, @p, @i, @d, @u, @dir, @q, @l, @s, @e, @n)'),
        parameters: {
          'id': newId(),
          'p': pharmacyId,
          'i': itemId,
          'd': drugId,
          'u': userId,
          'dir': direction,
          'q': quantity,
          'l': lot,
          's': serial,
          'e': expiry == null ? null : dateValue(expiry),
          'n': note,
        },
      );

  /// Stock intake. A karekod serial identifies one physical pack: it can be
  /// in stock only once, but a pack that was dispensed (quantity 0) and is
  /// returned can be taken in again.
  Future<StockItem> addBatch(String pharmacyId, String userId, String itemId,
      {String? lot, String? serial, DateTime? expiry, required int quantity}) async {
    if (quantity < 0) throw ApiError.badRequest('Adet negatif olamaz');
    if (serial != null && quantity != 1) throw ApiError.badRequest('Seri numaralı kutu tek adettir');
    await _ownItem(pharmacyId, itemId);
    final drugId = await _drugOf(itemId);
    await db.runTx((tx) async {
      if (serial != null) {
        final dup = await tx.execute(
            Sql.named('SELECT id, quantity FROM stock_batches WHERE item_id = @i AND serial = @s'),
            parameters: {'i': itemId, 's': serial});
        if (dup.isNotEmpty) {
          if ((dup.first[1] as int) > 0) {
            throw ApiError(409, 'duplicate_serial', 'Bu seri numaralı kutu zaten stokta');
          }
          await tx.execute(Sql.named('UPDATE stock_batches SET quantity = 1 WHERE id = @b'),
              parameters: {'b': dup.first[0]});
          await _move(tx, pharmacyId: pharmacyId, userId: userId, itemId: itemId, drugId: drugId,
              direction: 'giris', quantity: 1, lot: lot, serial: serial, expiry: expiry, note: 'iade/yeniden giriş');
          return;
        }
      }
      await tx.execute(
        Sql.named('INSERT INTO stock_batches (id, item_id, lot, serial, expiry, quantity) '
            'VALUES (@id, @i, @l, @s, @e, @q)'),
        parameters: {
          'id': newId(),
          'i': itemId,
          'l': lot,
          's': serial,
          'e': expiry == null ? null : dateValue(expiry),
          'q': quantity,
        },
      );
      if (quantity > 0) {
        await _move(tx, pharmacyId: pharmacyId, userId: userId, itemId: itemId, drugId: drugId,
            direction: 'giris', quantity: quantity, lot: lot, serial: serial, expiry: expiry);
      }
    });
    return (await list(pharmacyId, itemId: itemId)).single;
  }

  /// Stock removal (dispensing) from a scanned code.
  ///
  /// * Karekod with serial: that exact pack must be in stock; otherwise 404 —
  ///   another pack is never decremented in its place.
  /// * Lot/expiry without serial: a batch with the same lot (and expiry).
  /// * Plain barcode: the batch that expires first (FEFO); the response
  ///   says which batch was used.
  Future<({StockItem item, StockBatch batch})> dispense(String pharmacyId, String userId, String drugId,
      {String? serial, String? lot, DateTime? expiry, int quantity = 1}) async {
    if (quantity < 1) throw ApiError.badRequest('Adet en az 1 olmalı');
    final items = (await list(pharmacyId)).where((i) => i.drugId == drugId).toList();
    if (items.isEmpty) throw ApiError(404, 'not_in_stock', 'Bu ürün stokta kayıtlı değil');
    final item = items.single;
    final live = item.batches.where((b) => b.quantity > 0).toList();
    StockBatch? batch;
    if (serial != null) {
      batch = live.where((b) => b.serial == serial).firstOrNull;
      if (batch == null) {
        throw ApiError(404, 'serial_not_in_stock', 'Bu seri numaralı kutu stokta kayıtlı değil (seri $serial)');
      }
      if (quantity != 1) throw ApiError.badRequest('Seri numaralı kutu tek adettir');
    } else if (lot != null) {
      batch = live
          .where((b) => b.lot == lot && (expiry == null || b.expiry == null || _sameDay(b.expiry!, expiry)))
          .firstOrNull;
      if (batch == null) throw ApiError(404, 'lot_not_in_stock', 'Bu parti ($lot) stokta yok');
    } else {
      live.sort((a, b) => (a.expiry ?? DateTime(9999)).compareTo(b.expiry ?? DateTime(9999)));
      batch = live.firstOrNull;
      if (batch == null) throw ApiError(409, 'out_of_stock', 'Ürünün stokta adedi yok');
    }
    if (batch.quantity < quantity) {
      throw ApiError(409, 'insufficient', 'Partide yeterli adet yok (${batch.quantity})');
    }
    final b = batch;
    await db.runTx((tx) async {
      await tx.execute(Sql.named('UPDATE stock_batches SET quantity = quantity - @q WHERE id = @b'),
          parameters: {'q': quantity, 'b': b.id});
      await _move(tx, pharmacyId: pharmacyId, userId: userId, itemId: item.id, drugId: drugId,
          direction: 'cikis', quantity: quantity, lot: b.lot, serial: b.serial, expiry: b.expiry);
    });
    final updated = (await list(pharmacyId, itemId: item.id)).single;
    return (item: updated, batch: updated.batches.firstWhere((x) => x.id == b.id));
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Manual correction; the difference is logged.
  Future<void> setBatchQuantity(String pharmacyId, String userId, String batchId, int quantity, {String? note}) async {
    if (quantity < 0) throw ApiError.badRequest('Adet negatif olamaz');
    final r = await db.execute(
      Sql.named('SELECT b.quantity, b.item_id, i.drug_id, b.lot, b.serial, b.expiry FROM stock_batches b '
          'JOIN stock_items i ON i.id = b.item_id WHERE b.id = @b AND i.pharmacy_id = @p'),
      parameters: {'b': batchId, 'p': pharmacyId},
    );
    if (r.isEmpty) throw ApiError.notFound('Parti bulunamadı');
    final m = r.first.toColumnMap();
    final delta = quantity - (m['quantity'] as int);
    if (delta == 0) return;
    await db.runTx((tx) async {
      await tx.execute(Sql.named('UPDATE stock_batches SET quantity = @q WHERE id = @b'),
          parameters: {'q': quantity, 'b': batchId});
      await _move(tx, pharmacyId: pharmacyId, userId: userId, itemId: m['item_id'] as String,
          drugId: m['drug_id'] as String, direction: 'duzeltme', quantity: delta,
          lot: m['lot'] as String?, serial: m['serial'] as String?, expiry: m['expiry'] as DateTime?, note: note);
    });
  }

  Future<List<Map<String, dynamic>>> movements(String pharmacyId, {int limit = 100}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT m.id, m.direction, m.quantity, m.lot, m.serial, m.expiry, m.note, m.at,
               d.id AS drug_id, d.name AS drug_name, u.full_name AS user_name
        FROM stock_movements m JOIN drugs d ON d.id = m.drug_id JOIN users u ON u.id = m.user_id
        WHERE m.pharmacy_id = @p ORDER BY m.at DESC LIMIT @l'''),
      parameters: {'p': pharmacyId, 'l': limit},
    );
    return [
      for (final row in r)
        () {
          final m = row.toColumnMap();
          return {
            'id': m['id'],
            'direction': m['direction'],
            'quantity': m['quantity'],
            'lot': m['lot'],
            'serial': m['serial'],
            'expiry': (m['expiry'] as DateTime?)?.toIso8601String().substring(0, 10),
            'note': m['note'],
            'at': (m['at'] as DateTime).toUtc().toIso8601String(),
            'drugId': m['drug_id'],
            'drugName': m['drug_name'],
            'userName': m['user_name'],
          };
        }(),
    ];
  }

  Future<void> deleteItem(String pharmacyId, String itemId) async {
    final r = await db.execute(
        Sql.named('DELETE FROM stock_items WHERE id = @i AND pharmacy_id = @p'),
        parameters: {'i': itemId, 'p': pharmacyId});
    if (r.affectedRows == 0) throw ApiError.notFound('Stok kalemi bulunamadı');
  }

  /// Expiring batches, critical/out-of-stock items, and in-stock equivalents
  /// for out-of-stock items.
  Future<Map<String, dynamic>> alerts(String pharmacyId, {int days = 90}) async {
    final items = await list(pharmacyId);
    final now = DateTime.now();
    final expiring = <Map<String, dynamic>>[];
    for (final it in items) {
      for (final b in it.batches) {
        final d = b.daysToExpiry(now);
        if (d != null && d <= days && b.quantity > 0) {
          expiring.add({'item': it.toJson(), 'batch': b.toJson(), 'daysLeft': d});
        }
      }
    }
    expiring.sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));

    final inStock = {for (final it in items) if (!it.isOut) it.drugId: it};
    final out = <Map<String, dynamic>>[];
    for (final it in items.where((i) => i.isOut)) {
      final d = await drugs.byId(it.drugId);
      final alts = d == null ? <Drug>[] : await drugs.equivalents(d);
      out.add({
        'item': it.toJson(),
        'alternatives': [
          for (final a in alts)
            {'drug': a.toJson(), 'inStock': inStock[a.id]?.quantity ?? 0},
        ]..sort((a, b) => (b['inStock'] as int).compareTo(a['inStock'] as int)),
      });
    }
    return {
      'expiring': expiring,
      'critical': [for (final it in items.where((i) => i.isCritical)) it.toJson()],
      'outOfStock': out,
    };
  }
}

class AnnouncementRepo {
  AnnouncementRepo(this.db);
  final Db db;

  Future<List<Announcement>> list({AnnouncementType? type, int limit = 50}) async {
    final r = await db.execute(
      Sql.named('''
        SELECT a.id, a.type, a.title, a.summary, a.url, a.published_at,
               s.source AS s_source, s.version AS s_version, s.url AS s_url,
               s.fetched_at AS s_fetched_at, s.is_sample AS s_is_sample
        FROM announcements a JOIN data_sources s ON s.id = a.source_id AND s.active
        ${type == null ? '' : 'WHERE a.type = @t'}
        ORDER BY a.published_at DESC LIMIT @l'''),
      parameters: {'t': ?type?.name, 'l': limit},
    );
    return [
      for (final row in r)
        () {
          final m = row.toColumnMap();
          return Announcement(
            id: m['id'] as String,
            type: AnnouncementType.values.byName(m['type'] as String),
            title: m['title'] as String,
            summary: m['summary'] as String?,
            url: m['url'] as String?,
            publishedAt: m['published_at'] as DateTime,
            provenance: provenanceFromRow(m),
          );
        }(),
    ];
  }

  static Future<void> upsert(TxSession tx, Announcement a, int sourceId) => tx.execute(
        Sql.named('''
          INSERT INTO announcements (id, type, title, summary, url, published_at, source_id)
          VALUES (@id, @t, @title, @s, @u, @p, @src)
          ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title, summary = EXCLUDED.summary,
            type = EXCLUDED.type, source_id = EXCLUDED.source_id'''),
        parameters: {
          'id': a.id,
          't': a.type.name,
          'title': a.title,
          's': a.summary,
          'u': a.url,
          'p': a.publishedAt,
          'src': sourceId,
        },
      );
}

class FavoriteRepo {
  FavoriteRepo(this.db, this.drugs);
  final Db db;
  final DrugRepo drugs;

  Future<List<Drug>> list(String userId) async {
    final r = await db.execute(
        Sql.named('SELECT drug_id FROM favorites WHERE user_id = @u ORDER BY created_at DESC'),
        parameters: {'u': userId});
    return drugs.byIds([for (final x in r) x[0] as String]);
  }

  Future<void> add(String userId, String drugId) async {
    if (await drugs.byId(drugId) == null) throw ApiError.notFound('İlaç bulunamadı');
    await db.execute(
        Sql.named('INSERT INTO favorites (user_id, drug_id) VALUES (@u, @d) ON CONFLICT DO NOTHING'),
        parameters: {'u': userId, 'd': drugId});
  }

  Future<void> remove(String userId, String drugId) => db.execute(
      Sql.named('DELETE FROM favorites WHERE user_id = @u AND drug_id = @d'),
      parameters: {'u': userId, 'd': drugId});
}
