import 'dart:io';

import 'package:nux_wallet/services/store_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int _counter = 0;

/// StoreDatabase uji berbasis SQLite sungguhan (factory FFI)
/// pada berkas temp UNIK per panggilan — tiap test mendapat
/// basis data kosongnya sendiri, terisolasi persis seperti dulu
/// mereka terisolasi lewat SharedPreferences mock. (Berkas
/// `:memory:` tidak dipakai: factory sqflite meng-cache basis
/// data per path dalam satu proses, jadi antar-test bocor.)
/// Impor satu-kali tetap berjalan dari SharedPreferences
/// (mock) yang diatur test sebelum store pertama dibuka.
StoreDatabase newTestStoreDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _counter++;
  final dir = Directory.systemTemp.createTempSync('store_test_db');
  final path = p.join(
    dir.path,
    'store_pos_${DateTime.now().microsecondsSinceEpoch}_$_counter.db',
  );
  return StoreDatabase(dbPathProvider: () async => path);
}
