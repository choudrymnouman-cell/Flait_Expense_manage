import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/app_state.dart';
import 'secure_book.dart';
import 'live_sync.dart';

/// Signed ephemeral key exchange. Discovery contains no financial records.
class AutoHandshake {
  AutoHandshake._(
      this.identity, this.group, this.peer, this.key, this.publicKey);
  final DeviceIdentity identity;
  final String group, peer, publicKey;
  final SimpleKeyPair key;
  final String sid = randomCode();
  static Future<AutoHandshake> create(
      DeviceIdentity id, String group, String peer) async {
    final key = await X25519().newKeyPair();
    return AutoHandshake._(id, group, peer, key,
        base64Encode((await key.extractPublicKey()).bytes));
  }

  Future<Map<String, dynamic>> announcement(String change) => identity.sign({
        'v': 3,
        'group': group,
        'from': identity.publicId,
        'to': peer,
        'sid': sid,
        'key': publicKey,
        'change': change,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
  Future<String> accept(Map<String, dynamic> message) async {
    if (!await signedBy(message, peer)) {
      throw const FormatException('Untrusted device');
    }
    final b = asMap(message['body']);
    final at = DateTime.tryParse(b['at'] as String? ?? '');
    if (b['v'] != 3 ||
        b['group'] != group ||
        b['from'] != peer ||
        b['to'] != identity.publicId ||
        at == null ||
        DateTime.now().toUtc().difference(at).abs() >
            const Duration(minutes: 2) ||
        b['sid'] is! String ||
        (b['sid'] as String).length != 43 ||
        b['change'] is! String) {
      throw const FormatException('Invalid discovery');
    }
    final bytes = base64Decode(b['key'] as String);
    if (bytes.length != 32) throw const FormatException('Invalid key');
    final secret = await X25519().sharedSecretKey(
        keyPair: key,
        remotePublicKey: SimplePublicKey(bytes, type: KeyPairType.x25519));
    if ((await secret.extractBytes()).every((v) => v == 0)) {
      throw const FormatException('Invalid shared secret');
    }
    final endpoints = [
      {'id': identity.publicId, 'sid': sid, 'key': publicKey},
      {'id': peer, 'sid': b['sid'], 'key': b['key']},
    ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: secret,
        nonce: utf8.encode('Flait-auto-v3'),
        info: utf8.encode(canonical({'group': group, 'peers': endpoints})));
    return 'FLAIT2-${base64UrlEncode(await derived.extractBytes()).replaceAll('=', '')}';
  }
}

/// Runs only while the app is active. Offline changes stay in LocalDatabase.
class AutoSync extends ChangeNotifier {
  AutoSync(this.state) {
    state.addListener(_changed);
    _changed();
  }
  final FlaitState state;
  final Map<String, _Route> _routes = {};
  bool _active = true, _closed = false;
  String status = 'Automatic sync ready';
  final Map<String, DateTime> peerSeen = {};
  void setActive(bool active) {
    _active = active;
    _changed();
  }

  void report(String text) {
    if (!_closed) {
      status = text;
      notifyListeners();
    }
  }

  void _changed() {
    if (_closed) return;
    final id = state.identity, view = state.view;
    final peers = !_active ||
            id == null ||
            view == null ||
            view.members[id.publicId]?.active != true
        ? <String>{}
        : view.members.values
            .where((m) => m.active && m.id != id.publicId)
            .map((m) => m.id)
            .toSet();
    for (final peer in _routes.keys.toList()) {
      if (!peers.contains(peer)) {
        _routes.remove(peer)!.close();
      }
    }
    for (final peer in peers) {
      _routes.putIfAbsent(peer, () => _Route(this, peer));
    }
    for (final route in _routes.values) {
      route.changed();
    }
  }

  @override
  void dispose() {
    _closed = true;
    state.removeListener(_changed);
    for (final r in _routes.values) {
      r.close();
    }
    _routes.clear();
    super.dispose();
  }
}

class _Route {
  _Route(this.auto, this.peer) {
    unawaited(_open());
  }
  final AutoSync auto;
  FlaitState get state => auto.state;
  final String peer;
  SupabaseClient? client;
  RealtimeChannel? channel;
  AutoHandshake? handshake;
  SyncSession? session;
  Timer? timer;
  bool closed = false, busy = false, announcing = false, receiving = false;
  String fingerprint = '', tag = randomCode(), synced = '';
  Future<void> _open() async {
    try {
      handshake =
          await AutoHandshake.create(state.identity!, state.book!.id, peer);
      if (closed) return;
      final ids = [state.currentMemberId, peer]..sort();
      final room = await digest({'group': state.book!.id, 'peers': ids});
      if (closed) return;
      client = SupabaseClient('https://rrkzsrotgxqvrllilzbj.supabase.co',
          'sb_publishable_hEewjesFCyCW7IYAeJCo6A_WLizCGGQ');
      channel = client!.channel('flait-auto-v3-$room',
          opts: const RealtimeChannelConfig(ack: true));
      channel!.onBroadcast(
          event: 'discover',
          callback: (p) {
            unawaited(_receive(p));
          });
      channel!.subscribe((s, e) {
        if (closed) return;
        if (s == RealtimeSubscribeStatus.subscribed) {
          auto.report('Automatic sync on · waiting for flatmates');
          unawaited(_announce());
        } else {
          auto.report('Offline · saved locally, sync retries automatically');
        }
      });
      timer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_announce());
      });
    } catch (_) {
      if (!closed) {
        auto.report('Offline · automatic sync will retry');
        timer = Timer(const Duration(seconds: 10), () {
          if (!closed) unawaited(_open());
        });
      }
    }
  }

  void changed() {
    final next = canonical(state.sharedPacket());
    if (next != fingerprint) {
      fingerprint = next;
      tag = randomCode();
      unawaited(_announce());
    }
  }

  Future<void> _announce() async {
    if (closed || announcing || channel == null || handshake == null) return;
    announcing = true;
    try {
      await channel!.sendBroadcastMessage(
          event: 'discover', payload: await handshake!.announcement(tag));
    } catch (_) {
      auto.report('Offline · saved locally, sync retries automatically');
    } finally {
      announcing = false;
    }
  }

  Future<void> _receive(Map<String, dynamic> message) async {
    if (closed || receiving || handshake == null) return;
    receiving = true;
    try {
      final code = await handshake!.accept(message);
      if (closed) return;
      final b = asMap(message['body']);
      auto.peerSeen[peer] = DateTime.now();
      final token = '$tag:${b['sid']}:${b['change']}';
      if (busy || synced == token) return;
      busy = true;
      unawaited(_exchange(code, token));
      unawaited(_announce());
    } catch (_) {/* Unauthenticated or stale discovery is ignored. */} finally {
      receiving = false;
    }
  }

  Future<void> _exchange(String code, String token) async {
    final sync = SyncSession(state,
        host: state.currentMemberId.compareTo(peer) < 0,
        connectionCode: code,
        trustedPeerId: peer);
    session = sync;
    try {
      auto.report('Syncing automatically…');
      await sync.start(invite: code);
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!closed && !sync.completed && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!closed && sync.completed) {
        synced = token;
        await state.setPreference('peerSync', {
          ...asMap(state.preferences['peerSync'] ?? {}),
          peer: DateTime.now().toUtc().toIso8601String()
        });
        auto.report('Synced automatically · saved on this device');
      } else if (!closed) {
        auto.report('Waiting for flatmate · automatic retry enabled');
      }
    } catch (_) {
      if (!closed) {
        auto.report('Offline · saved locally, sync retries automatically');
      }
    } finally {
      await sync.close();
      sync.dispose();
      if (session == sync) session = null;
      busy = false;
    }
  }

  void close() {
    closed = true;
    timer?.cancel();
    unawaited(session?.close() ?? Future.value());
    unawaited(client?.dispose() ?? Future.value());
  }
}
