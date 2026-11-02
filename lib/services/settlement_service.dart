import '../models/flat_models.dart';

/// All allocation and settlement arithmetic uses integer minor units.
Map<String, int> allocateShares(int cents, Map<String, int> weights,
    {bool exact = false}) {
  if (cents <= 0 ||
      weights.isEmpty ||
      weights.length > 100 ||
      weights.values.any((v) => v < 0 || v > 1000000000000)) {
    throw ArgumentError('Choose members and valid shares.');
  }
  final sum = weights.values.fold(0, (a, b) => a + b);
  if (sum <= 0 || (exact && sum != cents)) {
    throw ArgumentError('Custom amounts must equal the expense total.');
  }
  if (exact) return Map.of(weights);
  final keys = weights.keys.toList()..sort();
  final result = {for (final k in keys) k: cents * weights[k]! ~/ sum};
  final remainders = [...keys]..sort((a, b) {
      final order =
          (cents * weights[b]! % sum).compareTo(cents * weights[a]! % sum);
      return order == 0 ? a.compareTo(b) : order;
    });
  final left = cents - result.values.fold(0, (a, b) => a + b);
  for (var i = 0; i < left; i++) {
    result[remainders[i]] = result[remainders[i]]! + 1;
  }
  return result;
}

class SettlementPayment {
  const SettlementPayment(this.from, this.to, this.cents);
  final String from, to;
  final int cents;
}

class SettlementService {
  Map<String, int> balances(Iterable<ExpenseRequest> expenses,
      Iterable<LedgerEntry> ledger, Iterable<SettlementPayment> payments) {
    final net = <String, int>{};
    void add(String id, int n) {
      net[id] = (net[id] ?? 0) + n;
    }

    for (final e in expenses) {
      if (e.cancelled ||
          e.shares.isEmpty ||
          ![ExpenseStatus.approved, ExpenseStatus.paid].contains(e.status)) {
        continue;
      }
      add(e.requesterId, (e.amount * 100).round());
      for (final share in e.shares.entries) {
        add(share.key, -share.value);
      }
    }
    // Pool contributions are money paid towards shared costs. Reimbursements
    // already received from the pool reduce the payer's remaining receivable.
    for (final e in ledger) {
      if (e.memberId == null) continue;
      if (e.type == LedgerType.contribution) {
        add(e.memberId!, (e.amount * 100).round());
      }
      if (e.type == LedgerType.expensePayment) {
        add(e.memberId!, -(e.amount * 100).round());
      }
    }
    for (final p in payments) {
      add(p.from, p.cents);
      add(p.to, -p.cents);
    }
    return net;
  }

  List<SettlementPayment> suggestions(Map<String, int> balances) {
    final debts = balances.entries
        .where((e) => e.value < 0)
        .map((e) => MapEntry(e.key, -e.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final credits = balances.entries
        .where((e) => e.value > 0)
        .map((e) => MapEntry(e.key, e.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final result = <SettlementPayment>[];
    var i = 0, j = 0;
    while (i < debts.length && j < credits.length) {
      final d = debts[i],
          c = credits[j],
          n = d.value < c.value ? d.value : c.value;
      result.add(SettlementPayment(d.key, c.key, n));
      debts[i] = MapEntry(d.key, d.value - n);
      credits[j] = MapEntry(c.key, c.value - n);
      if (debts[i].value == 0) i++;
      if (credits[j].value == 0) j++;
    }
    return result;
  }
}
