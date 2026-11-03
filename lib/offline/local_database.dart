import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:sembast/sembast.dart';
import 'device_key.dart';
import 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart';

class LocalDatabase {
  LocalDatabase(this.db, {this.encryptionKey, String recordId = 'device'})
      : _record = stringMapStoreFactory.store('flait_v2').record(recordId);
  LocalDatabase scoped(String id) =>
      LocalDatabase(db, encryptionKey: encryptionKey, recordId: id);
  final Database db;
  final SecretKey? encryptionKey;
  bool get encryptedAtRest => encryptionKey != null;
  final RecordRef<String, Map<String, Object?>> _record;
  static Future<LocalDatabase> open() async {
    final key = await deviceEncryptionKey();
    final database =
        LocalDatabase(await openDeviceDatabase(), encryptionKey: key);
    final data = await database.read();
    final raw = await database._record.get(database.db);
    if (data != null && key != null && raw?['encrypted'] != true) {
      await database.write(data, data['revision'] as int);
      await database.db.compact();
    }
    return database;
  }

  Future<Map<String, dynamic>?> read() async {
    final data = await _record.get(db);
    if (data == null) return null;
    if (data['encrypted'] != true) return Map<String, dynamic>.from(data);
    if (encryptionKey == null) {
      throw StateError(
          'Device encryption key unavailable. Restore a backup on a fresh installation.');
    }
    final bytes = await AesGcm.with256bits().decrypt(
        SecretBox(base64Decode(data['cipher'] as String),
            nonce: base64Decode(data['nonce'] as String),
            mac: Mac(base64Decode(data['mac'] as String))),
        secretKey: encryptionKey!,
        aad: utf8.encode('flait-device-v3:${data['revision']}'));
    final decoded =
        Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    if (decoded['revision'] != data['revision']) {
      throw StateError('Invalid local revision.');
    }
    return decoded;
  }

  Future<void> write(
      Map<String, dynamic> document, int expectedRevision) async {
    final next = {...document, 'revision': expectedRevision + 1};
    Map<String, dynamic> stored = next;
    if (encryptionKey != null) {
      final box = await AesGcm.with256bits().encrypt(
          utf8.encode(jsonEncode(next)),
          secretKey: encryptionKey!,
          aad: utf8.encode('flait-device-v3:${expectedRevision + 1}'));
      stored = {
        'encrypted': true,
        'revision': expectedRevision + 1,
        'cipher': base64Encode(box.cipherText),
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes)
      };
    }
    await db.transaction((txn) async {
      final old = await _record.get(txn);
      if ((old?['revision'] ?? 0) != expectedRevision) {
        throw StateError(
            'Data changed in another window. Reload before continuing.');
      }
      await _record.put(txn, stored);
    });
  }
}
