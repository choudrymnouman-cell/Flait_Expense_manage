import 'package:sembast/sembast.dart';
import 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart';

class LocalDatabase {
  LocalDatabase(this.db);
  final Database db;
  final _record = stringMapStoreFactory.store('flait_v2').record('device');
  static Future<LocalDatabase> open() async =>
      LocalDatabase(await openDeviceDatabase());
  Future<Map<String, dynamic>?> read() async {
    final data = await _record.get(db);
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  Future<void> write(
      Map<String, dynamic> document, int expectedRevision) async {
    await db.transaction((txn) async {
      final old = await _record.get(txn);
      if ((old?['revision'] ?? 0) != expectedRevision) {
        throw StateError(
            'Data changed in another window. Reload before continuing.');
      }
      await _record.put(txn, {...document, 'revision': expectedRevision + 1});
    });
  }
}
