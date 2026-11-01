import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../models/flat_models.dart';

// Versioned canonical encoding: signed maps are sorted recursively.
dynamic canonicalValue(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonicalValue(value[key])};
  }
  if (value is List) return value.map(canonicalValue).toList();
  return value;
}

String canonical(dynamic value) => jsonEncode(canonicalValue(value));
Map<String, dynamic> asMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);
List<Map<String, dynamic>> asMaps(dynamic value) =>
    (value as List).map(asMap).toList();
String randomCode() =>
    base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
Future<String> digest(dynamic value) async =>
    base64UrlEncode((await Sha256().hash(utf8.encode(canonical(value)))).bytes);

class DeviceIdentity {
  DeviceIdentity(this.seed, this.publicId, this.name);
  final String seed, publicId, name;
  static Future<DeviceIdentity> create(String name) async {
    final key = await Ed25519().newKeyPair();
    return DeviceIdentity(base64Encode(await key.extractPrivateKeyBytes()),
        base64Encode((await key.extractPublicKey()).bytes), name.trim());
  }

  Map<String, dynamic> toJson() => {'seed': seed, 'id': publicId, 'name': name};
  static Future<DeviceIdentity> fromJson(Map<String, dynamic> json) async {
    final key = await Ed25519()
        .newKeyPairFromSeed(base64Decode(json['seed'] as String));
    final id = base64Encode((await key.extractPublicKey()).bytes);
    if (id != json['id']) {
      throw const FormatException('Invalid device identity.');
    }
    return DeviceIdentity(json['seed'] as String, id, json['name'] as String);
  }

  Future<Map<String, dynamic>> sign(Map<String, dynamic> body) async {
    final key = await Ed25519().newKeyPairFromSeed(base64Decode(seed));
    final sig =
        await Ed25519().sign(utf8.encode(canonical(body)), keyPair: key);
    return {'body': body, 'sig': base64Encode(sig.bytes)};
  }
}

Future<bool> signedBy(Map<String, dynamic> signed, String id) async {
  try {
    return await Ed25519().verify(utf8.encode(canonical(signed['body'])),
        signature: Signature(base64Decode(signed['sig'] as String),
            publicKey:
                SimplePublicKey(base64Decode(id), type: KeyPairType.ed25519)));
  } catch (_) {
    return false;
  }
}

class BookView {
  BookView(
      this.owner, this.groupId, this.name, this.currency, String ownerName) {
    members[owner] =
        FlatMember(id: owner, name: ownerName, role: MemberRole.admin);
  }
  final String owner, groupId, name, currency;
  final Map<String, FlatMember> members = {};
  final Map<String, ExpenseRequest> expenses = {};
  final List<LedgerEntry> ledger = [];
  final Set<String> processed = {};
  final Map<String, String> rejected = {};
  List<Map<String, dynamic>> legacyArchive = [];
  int get balanceCents =>
      ledger.fold(0, (sum, e) => sum + (e.poolDelta * 100).round());
  bool manager(String id) =>
      members[id]?.role == MemberRole.admin ||
      members[id]?.role == MemberRole.treasurer;
  int cents(dynamic value) {
    if (value is! int || value <= 0 || value > 999999999999) {
      throw StateError('Invalid amount.');
    }
    return value;
  }

  String text(dynamic value, int min, int max) {
    if (value is! String || value.trim().length < min || value.length > max) {
      throw StateError('Invalid text.');
    }
    return value.trim();
  }

  // Only the owner's signed linear journal changes shared money. Member
  // operations remain proposals until the owner commits them, preventing
  // independent offline treasurers from spending the same balance.
  void apply(Map<String, dynamic> proposal) {
    final b = asMap(proposal['body']);
    final actor = b['author'] as String;
    final id = b['id'] as String;
    if (b['group'] != groupId || !members.containsKey(actor)) {
      throw StateError('Not a member of this flat.');
    }
    if (processed.contains(id)) throw StateError('Already processed.');
    final data = asMap(b['data']);
    final at = DateTime.parse(b['at'] as String);
    switch (b['kind']) {
      case 'member':
        if (actor != owner) {
          throw StateError('Only the owner can add flatmates.');
        }
        final key = data['id'] as String;
        if (base64Decode(key).length != 32 || members.containsKey(key)) {
          throw StateError('Member already exists or key is invalid.');
        }
        members[key] = FlatMember(
            id: key, name: text(data['name'], 1, 80), role: MemberRole.member);
      case 'role':
        if (actor != owner ||
            data['id'] == owner ||
            !members.containsKey(data['id'])) {
          throw StateError('Only the owner can set this role.');
        }
        final m = members[data['id']]!;
        if (!['member', 'treasurer'].contains(data['role'])) {
          throw StateError('Invalid role.');
        }
        members[m.id] = FlatMember(
            id: m.id,
            name: m.name,
            role: data['role'] == 'treasurer'
                ? MemberRole.treasurer
                : MemberRole.member);
      case 'expense':
        expenses[id] = ExpenseRequest(
            id: id,
            title: text(data['title'], 2, 120),
            description: text(data['description'], 0, 4000),
            category: text(data['category'], 1, 80),
            amount: cents(data['cents']) / 100,
            requesterId: actor,
            createdAt: at);
      case 'vote':
        final e = expenses[data['expense']];
        if (e == null ||
            e.status != ExpenseStatus.pending ||
            e.requesterId == actor ||
            e.votes.any((v) => v.memberId == actor) ||
            data['approve'] is! bool) {
          throw StateError(
              'This vote is not eligible or the request is already decided.');
        }
        final votes = [
          ...e.votes,
          ExpenseVote(
              memberId: actor, approved: data['approve'] as bool, at: at)
        ];
        final threshold = ((members.length - 1) ~/ 2) + 1;
        final yes = votes.where((v) => v.approved).length,
            no = votes.where((v) => !v.approved).length;
        expenses[e.id] = e.copyWith(
            votes: votes,
            status: yes >= threshold
                ? ExpenseStatus.approved
                : no >= threshold
                    ? ExpenseStatus.rejected
                    : ExpenseStatus.pending);
      case 'contribution':
        if (!manager(actor) || !members.containsKey(data['member'])) {
          throw StateError(
              'Only the owner or treasurer can record funds for a flatmate.');
        }
        ledger.add(LedgerEntry(
            id: id,
            type: LedgerType.contribution,
            amount: cents(data['cents']) / 100,
            actorId: actor,
            memberId: data['member'] as String,
            description: text(data['description'], 1, 4000),
            createdAt: at));
      case 'payment':
        final e = expenses[data['expense']];
        if (!manager(actor) ||
            e == null ||
            e.status != ExpenseStatus.approved) {
          throw StateError(
              'Only an approved unpaid request can be paid by a manager.');
        }
        if ((e.amount * 100).round() > balanceCents) {
          throw StateError('Insufficient pool funds.');
        }
        expenses[e.id] = e.copyWith(status: ExpenseStatus.paid, paidAt: at);
        ledger.add(LedgerEntry(
            id: id,
            type: LedgerType.expensePayment,
            amount: e.amount,
            actorId: actor,
            memberId: e.requesterId,
            description: 'Reimbursement: ${e.title}',
            createdAt: at,
            relatedExpenseId: e.id));
      case 'legacy':
        if (actor != owner || legacyArchive.isNotEmpty) {
          throw StateError(
              'Cloud archive can only be imported once by the owner.');
        }
        final rows = asMaps(data['rows']);
        if (rows.length > 10000) throw StateError('Archive too large.');
        legacyArchive = rows;
        final opening = data['openingCents'];
        if (opening is! int || opening < 0 || opening > 999999999999) {
          throw StateError('Invalid opening balance.');
        }
        if (opening > 0) {
          ledger.add(LedgerEntry(
              id: id,
              type: LedgerType.contribution,
              amount: opening / 100,
              actorId: owner,
              description: 'Opening balance from imported cloud archive',
              createdAt: at));
        }
      default:
        throw StateError('Unsupported operation.');
    }
  }
}

class SecureBook {
  SecureBook(this.manifest, this.records);
  final Map<String, dynamic> manifest;
  final List<Map<String, dynamic>> records;
  Map<String, dynamic> get details => asMap(manifest['body']);
  String get owner => details['owner'] as String;
  String get id => details['id'] as String;
  Map<String, dynamic> toJson() =>
      {'version': 2, 'manifest': manifest, 'records': records};
  static Future<SecureBook> create(DeviceIdentity identity, String name,
      {String currency = 'PKR'}) async {
    final m = await identity.sign({
      'id': const Uuid().v4(),
      'owner': identity.publicId,
      'ownerName': identity.name,
      'name': name.trim(),
      'currency': currency,
      'at': DateTime.now().toUtc().toIso8601String()
    });
    return SecureBook(m, []);
  }

  static Future<SecureBook> fromJson(Map<String, dynamic> json) async {
    if (json['version'] != 2) {
      throw const FormatException('Unsupported book version.');
    }
    final book = SecureBook(asMap(json['manifest']), asMaps(json['records']));
    await book.verify();
    return book;
  }

  BookView emptyView() => BookView(owner, id, details['name'] as String,
      details['currency'] as String, details['ownerName'] as String);
  Future<BookView> verify() async {
    if (records.length > 10000 ||
        !await signedBy(manifest, owner) ||
        base64Decode(owner).length != 32 ||
        (details['name'] as String).trim().isEmpty ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(details['currency'] as String)) {
      throw const FormatException('Invalid flat identity.');
    }
    final view = emptyView();
    var previous = await digest(manifest);
    for (var i = 0; i < records.length; i++) {
      final record = records[i],
          body = asMap(records[i]['body']),
          draft = asMap(asMap(records[i]['body'])['draft']);
      final proposal = asMap(draft['body']);
      if (body['seq'] != i ||
          body['previous'] != previous ||
          body['group'] != id ||
          !await signedBy(record, owner) ||
          proposal['group'] != id ||
          !await signedBy(draft, proposal['author'] as String) ||
          !view.members.containsKey(proposal['author']) ||
          view.processed.contains(proposal['id'])) {
        throw const FormatException(
            'Journal signature, order or membership check failed.');
      }
      if (body['rejected'] == true) {
        view.rejected[proposal['id'] as String] = body['reason'] as String;
      } else {
        view.apply(draft);
      }
      view.processed.add(proposal['id'] as String);
      previous = await digest(record);
    }
    return view;
  }

  Future<SecureBook> append(DeviceIdentity identity, Map<String, dynamic> draft,
      {bool keepRejection = false}) async {
    if (identity.publicId != owner) {
      throw StateError('Only the owner can finalize the shared journal.');
    }
    final v = await verify();
    final proposal = asMap(draft['body']);
    if (!await signedBy(draft, proposal['author'] as String) ||
        !v.members.containsKey(proposal['author']) ||
        proposal['group'] != id) {
      throw StateError('Invalid proposal signature or membership.');
    }
    if (v.processed.contains(proposal['id'])) return this;
    String? reason;
    try {
      v.apply(draft);
    } catch (e) {
      if (!keepRejection) rethrow;
      reason = e.toString();
    }
    final record = await identity.sign({
      'seq': records.length,
      'previous': await digest(records.isEmpty ? manifest : records.last),
      'group': id,
      'draft': draft,
      'rejected': reason != null,
      'reason': reason ?? ''
    });
    return SecureBook(manifest, [...records, record]);
  }

  Future<SecureBook> merge(SecureBook incoming) async {
    await incoming.verify();
    if (canonical(manifest) != canonical(incoming.manifest)) {
      throw StateError('This is a different flat.');
    }
    final overlap = min(records.length, incoming.records.length);
    for (var i = 0; i < overlap; i++) {
      if (canonical(records[i]) != canonical(incoming.records[i])) {
        throw StateError(
            'Conflicting owner histories. Restore the latest owner backup; do not use two owner devices.');
      }
    }
    return incoming.records.length > records.length ? incoming : this;
  }
}

Future<Map<String, dynamic>> makeProposal(DeviceIdentity identity,
        SecureBook book, String kind, Map<String, dynamic> data) =>
    identity.sign({
      'id': const Uuid().v4(),
      'group': book.id,
      'author': identity.publicId,
      'kind': kind,
      'data': data,
      'at': DateTime.now().toUtc().toIso8601String()
    });

class BackupCipher {
  static final aes = AesGcm.with256bits();
  static Future<String> encrypt(
      Map<String, dynamic> data, String password) async {
    if (password.length < 12) {
      throw ArgumentError('Use a backup password of at least 12 characters.');
    }
    final salt = aes.newNonce();
    final key = await Pbkdf2(
            macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256)
        .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final box = await aes.encrypt(utf8.encode(jsonEncode(data)),
        secretKey: key, aad: utf8.encode('flait-backup-v2'));
    return jsonEncode({
      'format': 'flait-backup-v2',
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes)
    });
  }

  static Future<Map<String, dynamic>> decrypt(
      String text, String password) async {
    if (text.length > 20000000) {
      throw const FormatException('Backup is too large.');
    }
    final data = asMap(jsonDecode(text));
    if (data['format'] != 'flait-backup-v2') {
      throw const FormatException('Not a Flait backup.');
    }
    final key =
        await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256)
            .deriveKey(
                secretKey: SecretKey(utf8.encode(password)),
                nonce: base64Decode(data['salt'] as String));
    final bytes = await aes.decrypt(
        SecretBox(base64Decode(data['cipher'] as String),
            nonce: base64Decode(data['nonce'] as String),
            mac: Mac(base64Decode(data['mac'] as String))),
        secretKey: key,
        aad: utf8.encode('flait-backup-v2'));
    return asMap(jsonDecode(utf8.decode(bytes)));
  }
}

void validateDraftShape(Map<String, dynamic> draft) {
  final b = asMap(draft['body']), d = asMap(b['data']);
  if (b['id'] is! String ||
      (b['id'] as String).length > 100 ||
      b['author'] is! String ||
      b['group'] is! String) {
    throw const FormatException('Malformed operation.');
  }
  DateTime.parse(b['at'] as String);
  switch (b['kind']) {
    case 'expense':
      if (d['title'] is! String ||
          d['description'] is! String ||
          d['category'] is! String ||
          d['cents'] is! int) {
        throw const FormatException('Malformed expense.');
      }
    case 'vote':
      if (d['expense'] is! String || d['approve'] is! bool) {
        throw const FormatException('Malformed vote.');
      }
    case 'payment':
      if (d['expense'] is! String) {
        throw const FormatException('Malformed payment.');
      }
    case 'contribution':
      if (d['cents'] is! int ||
          d['member'] is! String ||
          d['description'] is! String) {
        throw const FormatException('Malformed contribution.');
      }
    case 'member':
      if (d['id'] is! String || d['name'] is! String) {
        throw const FormatException('Malformed membership.');
      }
    case 'role':
      if (d['id'] is! String || d['role'] is! String) {
        throw const FormatException('Malformed role.');
      }
    case 'legacy':
      if (d['rows'] is! List || d['openingCents'] is! int) {
        throw const FormatException('Malformed archive.');
      }
    default:
      throw const FormatException('Unknown operation.');
  }
}
