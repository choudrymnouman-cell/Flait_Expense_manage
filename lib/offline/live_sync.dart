import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/app_state.dart';
import 'secure_book.dart';

// Client-origin Realtime Broadcast only: no tables, database triggers,
// replay, presence or persisted auth sessions. Payloads are encrypted BEFORE
// reaching the relay. The invitation key is never sent to the relay.
class LiveRelay {
  LiveRelay(this.onMessage, this.onStatus);
  final Future<void> Function(Map<String, dynamic>) onMessage;
  final void Function(String) onStatus;
  SupabaseClient? _client;
  RealtimeChannel? _channel;
  SecretKey? _key;
  String _room = '';
  final _aes = AesGcm.with256bits();
  final Map<String, Map<int, String>> _parts = {};
  final Set<String> _complete = {};
  bool _closed = false;
  Future<void> open(String code) async {
    final raw = code.trim().replaceFirst('FLAIT2-', '');
    final bytes = base64Url.decode(base64Url.normalize(raw));
    if (bytes.length != 32) throw const FormatException('Invalid sync code.');
    _key = SecretKey(bytes);
    _room = await digest({'key': raw});
    _client = SupabaseClient('https://rrkzsrotgxqvrllilzbj.supabase.co',
        'sb_publishable_hEewjesFCyCW7IYAeJCo6A_WLizCGGQ');
    _channel = _client!.channel('flait-live-v2-$_room',
        opts: const RealtimeChannelConfig(ack: true));
    final connected = Completer<void>();
    _channel!.onBroadcast(
        event: 'packet',
        callback: (payload) {
          unawaited(_receive(payload).catchError((Object e) {
            onStatus('Transfer failed: $e');
          }));
        });
    _channel!.subscribe((status, error) {
      if (_closed) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!connected.isCompleted) connected.complete();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        const message =
            'Connection unavailable. Your local data is safe. Reopen sync when online.';
        onStatus(message);
        if (!connected.isCompleted) {
          connected.completeError(StateError(message));
        }
      }
    });
    await connected.future.timeout(const Duration(seconds: 25));
  }

  Future<void> _receive(Map<String, dynamic> p) async {
    if (_closed || _key == null) return;
    final id = p['id'], index = p['i'], total = p['n'];
    if (id is! String ||
        id.length > 64 ||
        index is! int ||
        total is! int ||
        total < 1 ||
        total > 2500 ||
        index < 0 ||
        index >= total ||
        _complete.contains(id)) {
      return;
    }
    if (_parts.length > 8 && !_parts.containsKey(id)) {
      throw StateError('Too many incoming messages.');
    }
    final plain = await _aes.decrypt(
        SecretBox(base64Decode(p['c'] as String),
            nonce: base64Decode(p['v'] as String),
            mac: Mac(base64Decode(p['m'] as String))),
        secretKey: _key!,
        aad: utf8.encode('$_room:$id:$index:$total'));
    final parts = _parts.putIfAbsent(id, () => {});
    parts[index] = utf8.decode(plain);
    if (parts.length == total) {
      _parts.remove(id);
      _complete.add(id);
      if (_complete.length > 200) {
        throw StateError('Session message limit reached. Start a fresh sync.');
      }
      final joined = List.generate(total, (i) => parts[i]!).join();
      if (joined.length > 15000000) throw StateError('Transfer exceeds 10 MB.');
      await onMessage(asMap(jsonDecode(utf8.decode(base64Decode(joined)))));
    }
  }

  Future<void> send(Map<String, dynamic> value) async {
    if (_closed || _channel == null || _key == null) {
      throw StateError('Sync is not connected.');
    }
    final encoded = base64Encode(utf8.encode(jsonEncode(value)));
    if (encoded.length > 15000000) throw StateError('Transfer exceeds 10 MB.');
    const size = 6000;
    final total = (encoded.length / size).ceil(), id = randomCode();
    for (var i = 0; i < total; i++) {
      final end =
          (i + 1) * size < encoded.length ? (i + 1) * size : encoded.length;
      final box = await _aes.encrypt(
          utf8.encode(encoded.substring(i * size, end)),
          secretKey: _key!,
          aad: utf8.encode('$_room:$id:$i:$total'));
      final status =
          await _channel!.sendBroadcastMessage(event: 'packet', payload: {
        'id': id,
        'i': i,
        'n': total,
        'v': base64Encode(box.nonce),
        'm': base64Encode(box.mac.bytes),
        'c': base64Encode(box.cipherText)
      });
      if (status != ChannelResponse.ok) {
        throw StateError(
            'Message was not delivered. Reconnect and sync again.');
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    _parts.clear();
    _complete.clear();
    await _client?.dispose();
    _client = null;
    _channel = null;
    _key = null;
  }
}

class SyncSession extends ChangeNotifier {
  SyncSession(this.state, {this.host = true});
  final FlaitState state;
  final bool host;
  late final LiveRelay relay = LiveRelay(_receive, (text) {
    status = text;
    _notify();
  });
  String code = '', status = 'Not connected', sid = randomCode();
  String? peerId, peerSid, peerName;
  bool awaitingAdmission = false,
      connected = false,
      completed = false,
      _closed = false,
      _sendingHello = false;
  Timer? _helloTimer, _expiry;
  Future<void> _inbox = Future.value();
  Future<void> start({String? invite}) async {
    if (state.identity == null) throw StateError('Set your name first.');
    if (host && state.book == null) throw StateError('Create a flat first.');
    code = host ? 'FLAIT2-${randomCode()}' : invite!.trim();
    status = 'Connecting…';
    _notify();
    try {
      await relay.open(code);
      connected = true;
      status =
          host ? 'Waiting for the other device…' : 'Requesting a connection…';
      _notify();
      _expiry = Timer(const Duration(minutes: 10), () {
        status = 'Session expired. Create a fresh code.';
        _notify();
        unawaited(close());
      });
      if (!host) {
        await _hello();
        _helloTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!completed && peerId == null) unawaited(_hello());
        });
      }
    } catch (e) {
      status = e.toString();
      await relay.close();
      connected = false;
      _notify();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _signed(Map<String, dynamic> body) =>
      state.identity!
          .sign({...body, 'author': state.currentMemberId, 'sid': sid});
  Future<void> _hello() async {
    if (_closed || _sendingHello) return;
    _sendingHello = true;
    try {
      await relay.send(await _signed({
        'type': 'hello',
        'name': state.identity!.name,
        'group': state.book?.id
      }));
    } catch (e) {
      status = e.toString();
      _notify();
    } finally {
      _sendingHello = false;
    }
  }

  Future<void> _receive(Map<String, dynamic> signed) {
    final action = _inbox.then((_) => _handle(signed));
    _inbox = action.catchError((Object e) {
      status = 'Sync stopped: $e';
      _notify();
    });
    return _inbox;
  }

  Future<void> _handle(Map<String, dynamic> signed) async {
    if (_closed) return;
    final b = asMap(signed['body']);
    if (b['sid'] == sid) return;
    final author = b['author'] as String;
    if (!await signedBy(signed, author)) {
      throw const FormatException('Invalid device signature.');
    }
    if (b['type'] == 'hello' && host) {
      if (peerId != null && (peerId != author || peerSid != b['sid'])) return;
      if (b['group'] != null && b['group'] != state.book!.id) {
        throw StateError('The other device belongs to a different flat.');
      }
      peerId = author;
      peerSid = b['sid'] as String;
      peerName = b['name'] as String;
      if (!state.view!.members.containsKey(author)) {
        if (!state.isOwner) {
          throw StateError('Only the flat owner can admit a new member.');
        }
        awaitingAdmission = true;
        status = 'Confirm the new flatmate before sending any flat data.';
        _notify();
        return;
      }
      await _snapshot('offer');
      return;
    }
    if (b['target'] != sid) return;
    if (b['type'] == 'snapshot') {
      if (host &&
          (author != peerId || b['sid'] != peerSid || b['stage'] != 'reply')) {
        return;
      }
      if (!host &&
          peerId != null &&
          (author != peerId || b['sid'] != peerSid)) {
        return;
      }
      final packet = asMap(b['packet']);
      final received = await SecureBook.fromJson(asMap(packet['book']));
      final view = await received.verify();
      if (!view.members.containsKey(author)) {
        throw StateError('The sender is not a verified flatmate.');
      }
      await state.receivePacket(packet);
      peerId = author;
      peerSid = b['sid'] as String;
      _helloTimer?.cancel();
      if (host) {
        await _snapshot('final');
      } else if (b['stage'] == 'offer') {
        await _snapshot('reply');
      } else if (b['stage'] == 'final') {
        await relay.send(await _signed({
          'type': 'ack',
          'target': peerSid,
          'head': await digest(state.book!.toJson())
        }));
        completed = true;
        status = _success();
        await state.markSynced();
        _notify();
      }
    } else if (b['type'] == 'ack' &&
        host &&
        author == peerId &&
        b['sid'] == peerSid) {
      if (b['head'] != await digest(state.book!.toJson())) {
        throw StateError('Journal changed during sync. Sync once more.');
      }
      completed = true;
      status = _success();
      await state.markSynced();
      _notify();
    }
  }

  String _success() => state.queuedCount == 0
      ? 'Sync complete. Saved on both devices.'
      : 'Exchanged safely. ${state.queuedCount} changes still need a sync with the flat owner.';
  Future<void> approveMember() async {
    if (!awaitingAdmission || peerId == null) return;
    await state.addMember(peerId!, peerName!);
    awaitingAdmission = false;
    await _snapshot('offer');
  }

  Future<void> _snapshot(String stage) async {
    status = 'Transferring encrypted changes…';
    _notify();
    await relay.send(await _signed({
      'type': 'snapshot',
      'target': peerSid,
      'stage': stage,
      'packet': state.sharedPacket()
    }));
    status = 'Waiting for the other device to confirm…';
    _notify();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    connected = false;
    _helloTimer?.cancel();
    _expiry?.cancel();
    await relay.close();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
