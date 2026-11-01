import 'package:flutter/foundation.dart';
import '../models/flat_models.dart';
import '../services/accounting_service.dart';
import '../offline/local_database.dart';
import '../offline/secure_book.dart';

class FlaitState extends ChangeNotifier {
  FlaitState(this.storage);
  final LocalDatabase storage;
  final accounting = const AccountingService();
  DeviceIdentity? identity;
  SecureBook? book;
  BookView? view;
  List<Map<String, dynamic>> proposals = [];
  int revision = 0;
  bool loading = true, _disposed = false;
  String? loadError;
  String? lastSync;
  Future<void> _tail = Future.value();
  String get flatId => book?.id ?? '';
  String get flatName => view?.name ?? 'My flat';
  String get currency => view?.currency ?? 'PKR';
  String get currentMemberId => identity?.publicId ?? '';
  bool get isOwner => book != null && book!.owner == currentMemberId;
  List<FlatMember> get members => view?.members.values.toList() ?? [];
  FlatMember get currentMember =>
      view?.members[currentMemberId] ??
      FlatMember(
          id: currentMemberId,
          name: identity?.name ?? 'Member',
          role: MemberRole.member);
  List<LedgerEntry> get ledger => (view?.ledger.reversed.toList() ?? []);
  double get poolBalance => (view?.balanceCents ?? 0) / 100;
  int get queuedCount => proposals.length;
  int get pendingCount =>
      expenses.where((e) => e.status == ExpenseStatus.pending).length;
  List<ExpenseRequest> get expenses {
    final result = {...?view?.expenses};
    for (final draft in proposals) {
      final b = asMap(draft['body']), d = asMap(b['data']);
      if (b['kind'] == 'expense' && !result.containsKey(b['id'])) {
        result[b['id'] as String] = ExpenseRequest(
            id: b['id'] as String,
            title: d['title'] as String,
            description: d['description'] as String,
            category: d['category'] as String,
            amount: (d['cents'] as int) / 100,
            requesterId: b['author'] as String,
            createdAt: DateTime.parse(b['at'] as String));
      }
    }
    // Votes remain visibly queued; only owner-confirmed votes affect status.
    return result.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  bool voteQueued(String id) => proposals.any((p) {
        final b = asMap(p['body']);
        return b['kind'] == 'vote' &&
            b['author'] == currentMemberId &&
            asMap(b['data'])['expense'] == id;
      });
  bool paymentQueued(String id) => proposals.any((p) {
        final b = asMap(p['body']);
        return b['kind'] == 'payment' && asMap(b['data'])['expense'] == id;
      });
  String memberName(String id) => view?.members[id]?.name ?? 'Archived member';
  Map<String, dynamic> _document(DeviceIdentity? who, SecureBook? next,
          List<Map<String, dynamic>> queue) =>
      {
        'schema': 2,
        'identity': who?.toJson(),
        'book': next?.toJson(),
        'proposals': queue,
        'lastSync': lastSync,
      };
  Future<T> serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _save(DeviceIdentity? who, SecureBook? next,
      List<Map<String, dynamic>> queue) async {
    final nextView = next == null ? null : await next.verify();
    await storage.write(_document(who, next, queue), revision);
    identity = who;
    book = next;
    view = nextView;
    proposals = queue;
    revision++;
    notifyListeners();
  }

  Future<void> load() => serial(() async {
        loading = true;
        loadError = null;
        notifyListeners();
        try {
          final data = await storage.read();
          if (data != null) {
            if (data['schema'] != 2) {
              throw const FormatException(
                  'Unsupported local data. Restore a backup.');
            }
            final who = data['identity'] == null
                ? null
                : await DeviceIdentity.fromJson(asMap(data['identity']));
            final next = data['book'] == null
                ? null
                : await SecureBook.fromJson(asMap(data['book']));
            final nextView = next == null ? null : await next.verify();
            if (next != null && !nextView!.members.containsKey(who?.publicId)) {
              throw StateError(
                  'This device is not a member of the saved flat.');
            }
            identity = who;
            book = next;
            view = nextView;
            proposals = asMaps(data['proposals']);
            for (final draft in proposals) {
              validateDraftShape(draft);
              final b = asMap(draft['body']);
              if (next == null ||
                  b['group'] != next.id ||
                  !nextView!.members.containsKey(b['author']) ||
                  !await signedBy(draft, b['author'] as String)) {
                throw const FormatException('Invalid local proposal.');
              }
            }
            revision = data['revision'] as int;
            lastSync = data['lastSync'] as String?;
          }
        } catch (e) {
          loadError = e.toString();
        } finally {
          loading = false;
          notifyListeners();
        }
      });
  Future<void> prepareIdentity(String name) => serial(() async {
        if (name.trim().isEmpty || name.trim().length > 80) {
          throw ArgumentError('Enter a name of 1–80 characters.');
        }
        final who = identity == null
            ? await DeviceIdentity.create(name)
            : DeviceIdentity(identity!.seed, identity!.publicId, name.trim());
        await _save(who, book, proposals);
      });
  Future<void> createFlat(String name) => serial(() async {
        if (book != null ||
            identity == null ||
            name.trim().length < 2 ||
            name.trim().length > 80) {
          throw ArgumentError('Enter a flat name of 2–80 characters.');
        }
        await _save(identity, await SecureBook.create(identity!, name), []);
      });
  int _cents(double n) {
    if (!n.isFinite ||
        n < 0.01 ||
        n > 9999999999.99 ||
        (n * 100 - (n * 100).round()).abs() > 0.0001) {
      throw ArgumentError('Enter an amount with at most 2 decimal places.');
    }
    return (n * 100).round();
  }

  Future<void> operation(String kind, Map<String, dynamic> data,
          {String? operationId}) =>
      serial(() async {
        if (book == null || identity == null) {
          throw StateError('Create or join a flat first.');
        }
        if (operationId != null &&
            (view!.processed.contains(operationId) ||
                proposals.any((p) => asMap(p['body'])['id'] == operationId))) {
          return;
        }
        if (kind == 'vote' && voteQueued(data['expense'] as String)) {
          throw StateError('Your vote is already saved locally.');
        }
        if (kind == 'payment' && paymentQueued(data['expense'] as String)) {
          throw StateError('This payment is already queued.');
        }
        var draft = await makeProposal(identity!, book!, kind, data);
        if (operationId != null) {
          draft = await identity!
              .sign({...asMap(draft['body']), 'id': operationId});
        }
        // Check against the current confirmed view, before queueing local work.
        final preview = await book!.verify();
        if (kind == 'vote' && !preview.expenses.containsKey(data['expense'])) {
          throw StateError('Sync this request with the owner before voting.');
        }
        preview.apply(draft);
        if (isOwner) {
          await _save(
              identity, await book!.append(identity!, draft), proposals);
        } else {
          await _save(identity, book, [...proposals, draft]);
        }
      });
  Future<void> submitExpense(
          {required String title,
          required String description,
          required String category,
          required double amount}) =>
      operation('expense', {
        'title': title.trim(),
        'description': description.trim(),
        'category': category,
        'cents': _cents(amount)
      });
  Future<void> vote(String id, bool approve, {String comment = ''}) async {
    if (voteQueued(id)) {
      throw StateError(
          'Your vote is already saved locally. Sync with the owner.');
    }
    await operation('vote', {'expense': id, 'approve': approve});
  }

  Future<void> recordContribution(double amount, String description,
          {required String contributorId, required String requestId}) =>
      operation(
          'contribution',
          {
            'cents': _cents(amount),
            'member': contributorId,
            'description': description.trim().isEmpty
                ? 'Pool contribution'
                : description.trim()
          },
          operationId: requestId);
  Future<void> markPaid(String id) async {
    if (paymentQueued(id)) {
      throw StateError(
          'This payment is already queued for owner confirmation.');
    }
    await operation('payment', {'expense': id});
  }

  Future<void> setMemberRole(String id, MemberRole role) => operation('role', {
        'id': id,
        'role': role == MemberRole.treasurer ? 'treasurer' : 'member'
      });
  Future<void> addMember(String id, String name) async {
    if (view!.members.containsKey(id)) return;
    await operation('member', {'id': id, 'name': name});
  }

  Map<String, dynamic> sharedPacket() =>
      {'book': book!.toJson(), 'proposals': proposals};
  Future<void> receivePacket(Map<String, dynamic> packet) => serial(() async {
        var next = await SecureBook.fromJson(asMap(packet['book']));
        if (book != null) next = await book!.merge(next);
        var nextView = await next.verify();
        if (!nextView.members.containsKey(currentMemberId)) {
          throw StateError('The owner has not admitted this device.');
        }
        final all = <String, Map<String, dynamic>>{};
        for (final draft in [...proposals, ...asMaps(packet['proposals'])]) {
          validateDraftShape(draft);
          final b = asMap(draft['body']);
          if (b['group'] != next.id ||
              !nextView.members.containsKey(b['author']) ||
              !await signedBy(draft, b['author'] as String)) {
            throw const FormatException('Invalid or unauthorised proposal.');
          }
          final id = b['id'] as String;
          if (all.containsKey(id) && canonical(all[id]) != canonical(draft)) {
            throw StateError('Conflicting operation IDs.');
          }
          if (!nextView.processed.contains(id)) all[id] = draft;
        }
        if (all.length > 1000) throw StateError('Too many queued operations.');
        final queue = all.values.toList();
        // Requests precede votes; contributions precede payments. The owner then
        // serially validates every operation and signs accepted/rejected receipts.
        int priority(Map<String, dynamic> p) =>
            switch (asMap(p['body'])['kind']) {
              'expense' => 0,
              'contribution' => 1,
              'vote' => 2,
              'payment' => 3,
              _ => 4
            };
        queue.sort((a, b) {
          final order = priority(a).compareTo(priority(b));
          return order != 0 ? order : canonical(a).compareTo(canonical(b));
        });
        if (next.owner == currentMemberId) {
          for (final draft in queue) {
            next = await next.append(identity!, draft, keepRejection: true);
          }
          queue.clear();
        }
        nextView = await next.verify();
        await _save(
            identity,
            next,
            queue
                .where(
                    (p) => !nextView.processed.contains(asMap(p['body'])['id']))
                .toList());
      });
  Future<String> exportBackup(String password) =>
      BackupCipher.encrypt(_document(identity, book, proposals), password);
  Future<void> restoreBackup(String encoded, String password) =>
      serial(() async {
        final data = await BackupCipher.decrypt(encoded, password);
        final who = await DeviceIdentity.fromJson(asMap(data['identity']));
        final next = data['book'] == null
            ? null
            : await SecureBook.fromJson(asMap(data['book']));
        if (book != null) {
          throw StateError(
              'Restore is only available on a fresh installation. Your current flat has not been replaced.');
        }
        final queue = asMaps(data['proposals']);
        if (next != null) {
          final v = await next.verify();
          if (!v.members.containsKey(who.publicId)) {
            throw StateError('Backup identity is not a flat member.');
          }
          for (final draft in queue) {
            validateDraftShape(draft);
            final b = asMap(draft['body']);
            if (b['group'] != next.id ||
                !v.members.containsKey(b['author']) ||
                !await signedBy(draft, b['author'] as String)) {
              throw StateError('Invalid backup proposal.');
            }
          }
        }
        await _save(who, next, queue);
      });
  Future<void> markSynced() => serial(() async {
        lastSync = DateTime.now().toUtc().toIso8601String();
        await _save(identity, book, proposals);
      });
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
