import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../models/flat_models.dart';
import '../services/settlement_service.dart';

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
      this.owner, this.groupId, this.name, this.currency, String ownerName, {this.kind = 'legacy', this.invitee}) {
    members[owner] =
        FlatMember(id: owner, name: ownerName, role: MemberRole.admin);
  }
  final String kind;
  final String? invitee;
  final monthly = <String, Map<String, dynamic>>{};
  String owner;
  final String groupId, name, currency;
  String? transferOffer, transferTo;
  final List<SettlementPayment> settlements = [];
  final Map<String, List<Map<String, dynamic>>> history = {};
  final Set<String> recurringKeys = {};
  final Set<String> leaveRequests = {};
  final Map<String, FlatMember> members = {};
  final Map<String, ExpenseRequest> expenses = {};
  final List<LedgerEntry> ledger = [];
  final Set<String> processed = {};
  final Map<String, String> rejected = {};
  List<Map<String, dynamic>> legacyArchive = [];
  int get balanceCents =>
      ledger.fold(0, (sum, e) => sum + (e.poolDelta * 100).round());
  bool manager(String id) =>
      members[id]?.active == true &&
      (members[id]?.role == MemberRole.admin ||
          members[id]?.role == MemberRole.treasurer);
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

  Map<String, int> allocation(Map<String, dynamic> data, int total) {
    if (data['shares'] == null) return {}; // preserve pre-split histories
    final raw = asMap(data['shares']);
    if (raw.isEmpty ||
        raw.keys.any((k) => members[k]?.active != true) ||
        raw.values.any((v) => v is! int || v < 0)) {
      throw StateError('Invalid expense shares.');
    }
    final result = raw.map((k, v) => MapEntry(k, v as int));
    if (result.values.fold(0, (a, b) => a + b) != total) {
      throw StateError('Shares must equal the full amount.');
    }
    return result;
  }

  void applyMonthly(
    String id,
    String actor,
    String action,
    Map<String, dynamic> data,
    DateTime at,
  ) {
    final period = text(data['month'], 7, 7);
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      throw StateError('Invalid month.');
    }
    final active =
        members.values.where((m) => m.active).map((m) => m.id).toSet();
    Map<String, int> split(int amount) =>
        allocateShares(amount, {for (final member in active) member: 1});
    Map<String, dynamic> target(String type) {
      final row = monthly[data['target']];
      if (row == null || row['type'] != type) {
        throw StateError('Record not found.');
      }
      return row;
    }

    switch (action) {
      case 'meal_entry':
        if (kind != 'meal') throw StateError('Choose a meal group.');
        final amount = cents(data['cents']);
        final paid = asMap(data['paid']);
        if (paid.isEmpty ||
            paid.keys.any((key) => !active.contains(key)) ||
            paid.values.any((v) => v is! int || v < 0 || v > amount) ||
            paid.values.cast<int>().fold(0, (a, b) => a + b) != amount) {
          throw StateError('Payments must add up to the bill.');
        }
        monthly[id] = {
          'type': 'meal',
          'month': period,
          'title': text(data['title'], 1, 100),
          'cents': amount,
          'shares': split(amount),
          'paid': paid,
          'at': at.toIso8601String(),
        };
      case 'flat_budget':
        if ((kind != 'flat' && kind != 'legacy') || actor != owner) {
          throw StateError('Only the admin sets the monthly budget.');
        }
        final amount = cents(data['cents']);
        final budgetId = 'budget:$period';
        final old = monthly[budgetId];
        if (old != null) {
          final spent = monthly.values
              .where(
                (r) =>
                    r['type'] == 'item' &&
                    r['month'] == period &&
                    r['approved'] == true,
              )
              .fold<int>(0, (total, row) => total + (row['cents'] as int));
          if (amount < spent) {
            throw StateError('Budget cannot be below approved spending.');
          }
        }
        monthly[budgetId] = {
          'type': 'budget',
          'month': period,
          'cents': amount,
          'shares': split(amount),
        };
      case 'flat_item':
        if ((kind != 'flat' && kind != 'legacy') ||
            monthly['budget:$period'] == null) {
          throw StateError('Set the monthly flat budget first.');
        }
        final pay = data['pay'];
        if (pay != 'admin' && pay != 'individual') {
          throw StateError('Choose who paid.');
        }
        final row = <String, dynamic>{
          'type': 'item',
          'month': period,
          'title': text(data['title'], 1, 100),
          'cents': cents(data['cents']),
          'author': actor,
          'payer': pay == 'admin' ? owner : actor,
          'pay': pay,
          'eligible': active.toList(),
          'votes': [actor],
          'approved': active.length == 1,
        };
        monthly[id] = row;
      case 'flat_approve':
        final row = target('item');
        final votes = (row['votes'] as List).cast<String>();
        if (row['approved'] == true ||
            !(row['eligible'] as List).contains(actor) ||
            votes.contains(actor)) {
          throw StateError('Approval already recorded or unavailable.');
        }
        row['votes'] = [...votes, actor];
        row['approved'] = votes.length + 1 == (row['eligible'] as List).length;
      case 'loan_entry':
        if (kind != 'loan' || actor != owner || monthly.isNotEmpty) {
          throw StateError('One loan per invitation.');
        }
        final due = DateTime.tryParse(data['due'] as String? ?? '');
        if (due == null ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data['due'] as String)) {
          throw StateError('Choose a return date.');
        }
        if (data['direction'] != 'given' && data['direction'] != 'taken') {
          throw StateError('Choose a loan direction.');
        }
        monthly[id] = {
          'type': 'loan',
          'month': period,
          'cents': cents(data['cents']),
          'due': data['due'],
          'creator': actor,
          'direction': data['direction'],
          'returned': false,
        };
      case 'loan_return':
        final row = target('loan');
        final lender = row['direction'] == 'given'
            ? row['creator']
            : members.keys.where((key) => key != row['creator']).firstOrNull;
        if (actor != lender || row['returned'] == true) {
          throw StateError('The lender confirms the return.');
        }
        row['returned'] = true;
        row['returnMonth'] = period;
    }
  }

  // Only the owner's signed linear journal changes shared money. Member
  // operations remain proposals until the owner commits them, preventing
  // independent offline treasurers from spending the same balance.
  void apply(Map<String, dynamic> proposal) {
    final b = asMap(proposal['body']);
    final actor = b['author'] as String;
    final id = b['id'] as String;
    if (b['group'] != groupId ||
        !members.containsKey(actor) ||
        !members[actor]!.active) {
      throw StateError('Not a member of this flat.');
    }
    if (processed.contains(id)) throw StateError('Already processed.');
    final data = asMap(b['data']);
    final at = DateTime.parse(b['at'] as String);
    switch (b['kind']) {
      case 'meal_entry':
      case 'flat_budget':
      case 'flat_item':
      case 'flat_approve':
      case 'loan_entry':
      case 'loan_return':
        applyMonthly(id, actor, b['kind'] as String, data, at);
      case 'member':
        if (actor != owner) {
          throw StateError('Only the owner can add flatmates.');
        }
        final key = data['id'] as String;
        if (kind == 'loan' &&
            (members.length >= 2 || (invitee != null && key != invitee))) {
          throw StateError('This loan invitation is for one person.');
        }
        if (base64Decode(key).length != 32 || members.containsKey(key)) {
          throw StateError('Member already exists or key is invalid.');
        }
        members[key] = FlatMember(
          id: key,
          name: text(data['name'], 1, 80),
          role: MemberRole.member,
        );
        final budget = monthly['budget:${data['budgetMonth']}'];
        if (budget != null) {
          budget['shares'] = allocateShares(budget['cents'] as int, {
            for (final member in members.values)
              if (member.active) member.id: 1,
          });
        }
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
            active: m.active,
            role: data['role'] == 'treasurer'
                ? MemberRole.treasurer
                : MemberRole.member);
      case 'leave_request':
        if (actor == owner) {
          throw StateError('Transfer ownership before leaving.');
        }
        leaveRequests.add(actor);
      case 'member_active':
        final m = members[data['id']];
        if (actor != owner ||
            m == null ||
            m.id == owner ||
            data['active'] is! bool) {
          throw StateError('Only the owner can revoke/reactivate a member.');
        }
        if (data['active'] == false &&
            data['security'] != true &&
            expenses.values.any((e) =>
                !e.cancelled &&
                [ExpenseStatus.pending, ExpenseStatus.approved]
                    .contains(e.status) &&
                (e.requesterId == m.id || (e.shares[m.id] ?? 0) > 0))) {
          throw StateError(
              'Resolve pending/unpaid claims involving this member first.');
        }
        if (data['active'] == false &&
            data['security'] != true &&
            (SettlementService()
                        .balances(expenses.values, ledger, settlements)[m.id] ??
                    0) !=
                0) {
          throw StateError(
              'Settle this member’s confirmed balance before removal.');
        }
        leaveRequests.remove(m.id);
        members[m.id] = FlatMember(
            id: m.id,
            name: m.name,
            role: m.role,
            active: data['active'] as bool);
      case 'transfer_offer':
        if (actor != owner ||
            data['to'] == owner ||
            members[data['to']]?.active != true) {
          throw StateError('Choose an active flatmate.');
        }
        transferOffer = id;
        transferTo = data['to'] as String;
      case 'transfer_cancel':
        if (actor != owner) {
          throw StateError('Only the owner can cancel transfer.');
        }
        transferOffer = null;
        transferTo = null;
      case 'transfer_accept':
        if (actor != transferTo ||
            data['offer'] != transferOffer ||
            transferOffer == null) {
          throw StateError('No matching owner transfer offer.');
        }
        final old = members[owner]!, next = members[actor]!;
        members[old.id] =
            FlatMember(id: old.id, name: old.name, role: MemberRole.member);
        members[next.id] =
            FlatMember(id: next.id, name: next.name, role: MemberRole.admin);
        owner = actor;
        transferOffer = null;
        transferTo = null;
      case 'expense':
        final recurring = data['recurringKey'] as String?;
        if (recurring != null &&
            (recurring.length > 120 || !recurringKeys.add(recurring))) {
          throw StateError('This recurring bill is already recorded.');
        }
        final amount = cents(data['cents']);
        final shares = allocation(data, amount);
        final receipt = validateReceipt(data['receipt']);
        expenses[id] = ExpenseRequest(
            id: id,
            title: text(data['title'], 2, 120),
            description: text(data['description'], 0, 4000),
            category: text(data['category'], 1, 80),
            amount: amount / 100,
            requesterId: actor,
            createdAt: at,
            shares: shares,
            receiptReference: receipt,
            recurringKey: recurring);
        history[id] = [
          {
            'at': b['at'],
            'actor': actor,
            'action': 'created',
            'data': Map.of(data)
          }
        ];
      case 'amend':
        final e = expenses[data['expense']];
        if (e == null ||
            e.cancelled ||
            e.status != ExpenseStatus.pending ||
            e.requesterId != actor ||
            data['revision'] != e.revision) {
          throw StateError(
              'Only the requester can correct a pending request at its current revision.');
        }
        final amount = cents(data['cents']);
        final shares = allocation(data, amount);
        final reason = text(data['reason'], 3, 300);
        expenses[e.id] = e.copyWith(
            title: text(data['title'], 2, 120),
            description: text(data['description'], 0, 4000),
            category: text(data['category'], 1, 80),
            amount: amount / 100,
            shares: shares,
            votes: [],
            revision: e.revision + 1,
            receiptReference: validateReceipt(data['receipt']));
        history[e.id]!.add({
          'at': b['at'],
          'actor': actor,
          'action': 'corrected',
          'reason': reason,
          'data': Map.of(data)
        });
      case 'cancel':
        final e = expenses[data['expense']];
        if (e == null ||
            e.cancelled ||
            e.status == ExpenseStatus.paid ||
            (actor != owner && actor != e.requesterId)) {
          throw StateError('A paid or cancelled expense cannot be cancelled.');
        }
        expenses[e.id] = e.copyWith(
            cancelled: true,
            status: ExpenseStatus.rejected,
            revision: e.revision + 1);
        history[e.id]!.add({
          'at': b['at'],
          'actor': actor,
          'action': 'cancelled',
          'reason': text(data['reason'], 3, 300)
        });
      case 'settlement':
        final from = data['from'] as String,
            to = data['to'] as String,
            n = cents(data['cents']);
        if (!members.containsKey(from) ||
            !members.containsKey(to) ||
            from == to ||
            ![owner, from, to].contains(actor)) {
          throw StateError(
              'Only the payer, recipient or owner can record this settlement.');
        }
        final net =
            SettlementService().balances(expenses.values, ledger, settlements);
        if ((net[from] ?? 0) >= 0 ||
            (net[to] ?? 0) <= 0 ||
            n > -(net[from] ?? 0) ||
            n > (net[to] ?? 0)) {
          throw StateError('Settlement exceeds current confirmed dues.');
        }
        settlements.add(SettlementPayment(from, to, n));
      case 'vote':
        final e = expenses[data['expense']];
        if (e == null ||
            e.status != ExpenseStatus.pending ||
            e.cancelled ||
            (data['revision'] ?? 0) != e.revision ||
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
        final threshold = ((members.values
                    .where((m) => m.active && m.id != e.requesterId)
                    .length) ~/
                2) +
            1;
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
        if (!manager(actor) || members[data['member']]?.active != true) {
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
            (e.status != ExpenseStatus.approved || e.cancelled)) {
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
  String get originOwner => details['owner'] as String;
  String get owner {
    var result = originOwner;
    for (final r in records) {
      final b = asMap(r['body']);
      final d = asMap(asMap(b['draft'])['body']);
      if (b['rejected'] != true && d['kind'] == 'transfer_accept') {
        result = d['author'] as String;
      }
    }
    return result;
  }

  String get id => details['id'] as String;
  Map<String, dynamic> toJson() =>
      {'version': 3, 'manifest': manifest, 'records': records};
  static Future<SecureBook> create(DeviceIdentity identity, String name,
      {String currency = 'PKR', String kind = 'legacy', String? invitee}) async {
    final m = await identity.sign({
      'id': const Uuid().v4(),
      'owner': identity.publicId,
      'ownerName': identity.name,
      'name': name.trim(),
      'currency': currency,
      if (kind != 'legacy') 'kind': kind,
      if (invitee != null) 'invitee': invitee,
      'at': DateTime.now().toUtc().toIso8601String()
    });
    return SecureBook(m, []);
  }

  static Future<SecureBook> fromJson(Map<String, dynamic> json) async {
    if (![2, 3].contains(json['version'])) {
      throw const FormatException('Unsupported book version.');
    }
    final book = SecureBook(asMap(json['manifest']), asMaps(json['records']));
    await book.verify();
    return book;
  }

  BookView emptyView() => BookView(originOwner, id, details['name'] as String,
      details['currency'] as String, details['ownerName'] as String,
      kind: details['kind'] as String? ?? 'legacy',
      invitee: details['invitee'] as String?);
  Future<BookView> verify() async {
    if (records.length > 10000 ||
        !await signedBy(manifest, originOwner) ||
        base64Decode(originOwner).length != 32 ||
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
          !await signedBy(record, view.owner) ||
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
    final result = SecureBook(manifest, [...records, record]);
    if (utf8.encode(canonical(result.toJson())).length > 6000000) {
      throw StateError(
          'Shared history reached the 6 MB live-sync limit. Export a backup and start a new accounting period.');
    }
    return result;
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
    case 'meal_entry':
    case 'flat_budget':
    case 'flat_item':
    case 'flat_approve':
    case 'loan_entry':
    case 'loan_return':
      if (d['month'] is! String) throw const FormatException('Invalid month.');
    case 'expense':
      if (d['title'] is! String ||
          d['description'] is! String ||
          d['category'] is! String ||
          d['cents'] is! int) {
        throw const FormatException('Malformed expense.');
      }
    case 'amend':
      if (d['expense'] is! String ||
          d['revision'] is! int ||
          d['title'] is! String ||
          d['description'] is! String ||
          d['category'] is! String ||
          d['cents'] is! int ||
          d['reason'] is! String) {
        throw const FormatException('Malformed correction.');
      }
    case 'cancel':
      if (d['expense'] is! String || d['reason'] is! String) {
        throw const FormatException('Malformed cancellation.');
      }
    case 'leave_request':
      break;
    case 'member_active':
      if (d['id'] is! String || d['active'] is! bool) {
        throw const FormatException('Malformed membership change.');
      }
    case 'transfer_offer':
      if (d['to'] is! String) {
        throw const FormatException('Malformed transfer.');
      }
    case 'transfer_accept':
      if (d['offer'] is! String) {
        throw const FormatException('Malformed transfer acceptance.');
      }
    case 'transfer_cancel':
      break;
    case 'settlement':
      if (d['from'] is! String || d['to'] is! String || d['cents'] is! int) {
        throw const FormatException('Malformed settlement.');
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

String? validateReceipt(dynamic value) {
  if (value == null) return null;
  if (value is! String || value.length > 700000) {
    throw StateError('Receipt exceeds 500 KB.');
  }
  final bytes = base64Decode(value);
  if (bytes.length > 500000 || bytes.length < 24) {
    throw StateError('Choose a JPEG or PNG photo below 500 KB.');
  }
  int width = 0, height = 0;
  if (bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71) {
    int u32(int p) =>
        (bytes[p] << 24) |
        (bytes[p + 1] << 16) |
        (bytes[p + 2] << 8) |
        bytes[p + 3];
    width = u32(16);
    height = u32(20);
  } else if (bytes[0] == 255 && bytes[1] == 216) {
    var p = 2;
    while (p + 4 < bytes.length) {
      if (bytes[p++] != 255) continue;
      while (p < bytes.length && bytes[p] == 255) {
        p++;
      }
      if (p >= bytes.length) break;
      final marker = bytes[p++];
      if (marker == 217 || marker == 218) break;
      if (marker == 0 || marker == 1 || (marker >= 208 && marker <= 215)) {
        continue;
      }
      if (p + 1 >= bytes.length) break;
      final length = (bytes[p] << 8) | bytes[p + 1];
      if (length < 2 || p + length > bytes.length) break;
      if ([192, 193, 194, 195, 197, 198, 199, 201, 202, 203, 205, 206, 207]
              .contains(marker) &&
          length >= 7) {
        height = (bytes[p + 3] << 8) | bytes[p + 4];
        width = (bytes[p + 5] << 8) | bytes[p + 6];
        break;
      }
      p += length;
    }
  }
  if (width < 1 ||
      height < 1 ||
      width > 8192 ||
      height > 8192 ||
      width * height > 16000000) {
    throw StateError('Use a valid JPEG/PNG of at most 16 megapixels.');
  }
  return value;
}
