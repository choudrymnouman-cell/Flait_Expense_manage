import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

Future<SecretKey?> deviceEncryptionKey() async {
  if (kIsWeb) {
    return null; // Browser storage relies on its origin/device protection.
  }
  const secure = FlutterSecureStorage();
  var encoded = await secure.read(key: 'flait.database.v3');
  if (encoded == null) {
    final key = await AesGcm.with256bits().newSecretKey();
    encoded = base64Encode(await key.extractBytes());
    await secure.write(key: 'flait.database.v3', value: encoded);
  }
  return SecretKey(base64Decode(encoded));
}
