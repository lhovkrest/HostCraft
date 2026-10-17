import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_info.dart';
import '../core/progress.dart';

/// Thrown internally when a server ignores `Range` requests, so the caller can
/// fall back to a normal single-connection download.
class _NoRanges implements Exception {
  const _NoRanges();
}

class _Stop {
  bool value = false;
}

class DownloadService {
  DownloadService({
    this.onProgress,
    this.onDetail,
    this.onNote,
    this.contact = '',
    this.curseForgeKey = '',
    this.client,
  });

  /// Coarse progress: a label and 0..1 (null when unknown).
  final void Function(String label, double? progress)? onProgress;

  /// Byte-level progress with speed, shown in the console.
  final void Function(DownloadProgress progress)? onDetail;

  /// Short messages worth a console line (for example a fallback).
  final void Function(String message)? onNote;

  // Set your own contact URL before distributing a Paper-enabled build.
  final String contact;
  final String curseForgeKey;
  final http.Client? client;
  http.Client get _http => client ?? _client;

  /// Files at least this big are fetched in several pieces at once when the
  /// server supports it. One connection is often throttled well below what the
  /// link can carry, especially on phones.
  static const _parallelMinBytes = 8 * 1024 * 1024;
  static const _segments = 4;

  /// One shared client: connections are kept alive and reused, so the several
  /// small lookups before a download do not each pay for a new TLS handshake.
  /// The connect timeout stops a dead IPv6 route from stalling a download.
  static final http.Client _client = IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 8,
  );

  Map<String, String> headers(String url) => {
    'User-Agent':
        'HostCraft/$appVersion${contact.isEmpty || !Uri.parse(url).host.endsWith('papermc.io') ? '' : ' ($contact)'}',
    if (curseForgeKey.isNotEmpty &&
        Uri.parse(url).scheme == 'https' &&
        (Uri.parse(url).host == 'forgecdn.net' ||
            Uri.parse(url).host.endsWith('.forgecdn.net')))
      'x-api-key': curseForgeKey,
  };

  // Resolve redirects ourselves so a CDN key never follows a redirect to an
  // unrelated host. Recompute credentials for each destination, including HEAD
  // probes and every range request.
  Future<http.StreamedResponse> _send(http.Request request) async {
    var current = request;
    for (var redirects = 0; redirects <= 5; redirects++) {
      current.followRedirects = false;
      final response = await _http
          .send(current)
          .timeout(const Duration(seconds: 45));
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      await response.stream.drain<void>();
      if (location == null || redirects == 5) {
        throw const HttpException('Download redirect could not be resolved');
      }
      final next = current.url.resolve(location);
      if (next.scheme != 'https') {
        throw const HttpException('Download redirects must use HTTPS');
      }
      final range = current.headers['Range'];
      current = http.Request(current.method, next)
        ..headers.addAll(headers(next.toString()));
      if (range != null) current.headers['Range'] = range;
    }
    throw const HttpException('Too many download redirects');
  }

  Future<dynamic> json(String url) async {
    return jsonDecode(await text(url));
  }

  Future<String> text(String url) async {
    final response = await _http
        .get(Uri.parse(url), headers: headers(url))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode} from ${Uri.parse(url).host}',
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  /// Reports a phase that has no byte counts (extracting, installing).
  void step(String label) {
    onProgress?.call(label, null);
    onDetail?.call(DownloadProgress.step(label));
  }

  Future<void> file(
    String url,
    File target, {
    String? checksum,
    String algorithm = 'sha256',
    String label = 'Downloading',
  }) async {
    if (Uri.parse(url).scheme != 'https') {
      throw ArgumentError('Downloads must use HTTPS');
    }
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final meter = _Meter(label, (p) {
      onDetail?.call(p);
      onProgress?.call(label, p.done && !p.failed ? 1.0 : p.fraction);
    });
    var finished = false;
    try {
      final size = await _rangeSize(url);
      var done = false;
      if (size != null && size >= _parallelMinBytes) {
        try {
          await _parallel(url, part, size, meter);
          done = true;
        } on _NoRanges {
          onNote?.call(
            'This server does not allow split downloads. Using one connection.',
          );
        } catch (e) {
          onNote?.call(
            'Split download failed ($e). Retrying on one connection.',
          );
        }
        if (!done) {
          meter.reset();
          if (await part.exists()) await part.delete();
        }
      }
      if (!done) await _single(url, part, meter);
      if (checksum != null) {
        final hash = switch (algorithm) {
          'sha1' => sha1,
          'md5' => md5,
          _ => sha256,
        };
        final actual = await hash.bind(part.openRead()).first;
        if (actual.toString().toLowerCase() != checksum.toLowerCase()) {
          throw const FormatException('Download checksum mismatch');
        }
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      finished = true;
      meter.finish();
    } finally {
      if (!finished) meter.fail();
      if (await part.exists()) await part.delete();
    }
  }

  /// Size of the file when the server announces it and accepts byte ranges,
  /// otherwise null.
  Future<int?> _rangeSize(String url) async {
    try {
      final request = http.Request('HEAD', Uri.parse(url))
        ..headers.addAll(headers(url));
      final response = await _send(request)
          .timeout(const Duration(seconds: 20));
      await response.stream.drain<void>();
      final length = response.contentLength;
      final ranges = response.headers['accept-ranges']?.toLowerCase();
      if (response.statusCode == 200 &&
          length != null &&
          length > 0 &&
          ranges == 'bytes') {
        return length;
      }
    } catch (_) {
      // Not being able to probe only means a normal download.
    }
    return null;
  }

  Future<void> _single(String url, File part, _Meter meter) async {
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll(headers(url));
      final response = await _send(request)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw HttpException(
          'HTTP ${response.statusCode} downloading ${meter.label}',
        );
      }
      meter.start(response.contentLength);
      sink = part.openWrite();
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 90),
      )) {
        sink.add(bytes);
        meter.add(bytes.length);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      final expected = response.contentLength;
      if (expected != null && meter.received != expected) {
        throw const HttpException('Incomplete download');
      }
    } finally {
      await sink?.close();
    }
  }

  Future<void> _parallel(String url, File part, int size, _Meter meter) async {
    meter.start(size);
    await part.create(recursive: true);
    final file = await part.open(mode: FileMode.write);
    final stop = _Stop();
    var chain = Future<void>.value();
    // A RandomAccessFile allows one operation at a time, so writes from the
    // pieces are queued one after another.
    Future<void> write(int position, List<int> data) {
      if (stop.value) return Future<void>.value();
      final next = chain.then((_) async {
        await file.setPosition(position);
        await file.writeFrom(data);
      });
      chain = next.then((_) {}, onError: (Object _) {});
      return next;
    }

    try {
      await file.truncate(size);
      final piece = (size / _segments).ceil();
      final jobs = <Future<void>>[];
      for (var i = 0; i < _segments; i++) {
        final start = i * piece;
        if (start >= size) break;
        final end = math.min(size, start + piece) - 1;
        jobs.add(_segment(url, start, end, size, write, meter, stop));
      }
      await Future.wait(jobs, eagerError: true);
      await chain;
      await file.flush();
    } catch (_) {
      stop.value = true;
      rethrow;
    } finally {
      stop.value = true;
      await chain;
      await file.close();
    }
    if (await part.length() != size) {
      throw const HttpException('Incomplete download');
    }
  }

  Future<void> _segment(
    String url,
    int start,
    int end,
    int size,
    Future<void> Function(int position, List<int> data) write,
    _Meter meter,
    _Stop stop,
  ) async {
    final request = http.Request('GET', Uri.parse(url))
      ..headers.addAll(headers(url))
      ..headers['Range'] = 'bytes=$start-$end';
    final response = await _send(request).timeout(const Duration(seconds: 45));
    if (response.statusCode != 206) {
      // Never drain a full 200 body: cancel it so the connection is dropped.
      final sub = response.stream.listen((_) {});
      await sub.cancel();
      if (response.statusCode == 200) throw const _NoRanges();
      throw HttpException(
        'HTTP ${response.statusCode} downloading ${meter.label}',
      );
    }
    final range = RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)')
        .firstMatch(response.headers['content-range'] ?? '');
    if (range == null ||
        int.parse(range[1]!) != start ||
        int.parse(range[2]!) != end) {
      final sub = response.stream.listen((_) {});
      await sub.cancel();
      throw const _NoRanges();
    }
    var position = start;
    await for (final bytes in response.stream.timeout(
      const Duration(seconds: 90),
    )) {
      if (stop.value) return;
      await write(position, bytes);
      position += bytes.length;
      meter.add(bytes.length);
    }
    if (position != end + 1) {
      throw const HttpException('Incomplete download piece');
    }
  }
}

/// Counts bytes and turns them into [DownloadProgress] snapshots, about four
/// a second, with a speed averaged over the last three seconds.
class _Meter {
  _Meter(this.label, this.emit) {
    reset();
  }
  final String label;
  final void Function(DownloadProgress) emit;
  int received = 0;
  int? total;
  double _speed = 0;
  late DateTime _started;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  final _samples = <(DateTime, int)>[];

  void reset() {
    received = 0;
    _speed = 0;
    _started = DateTime.now();
    _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    _samples
      ..clear()
      ..add((_started, 0));
  }

  void start(int? size) {
    total = size;
    emit(_snapshot());
  }

  void add(int bytes) {
    received += bytes;
    final now = DateTime.now();
    if (now.difference(_lastEmit).inMilliseconds < 250) return;
    _lastEmit = now;
    _samples.add((now, received));
    while (_samples.length > 2 &&
        now.difference(_samples.first.$1).inMilliseconds > 3000) {
      _samples.removeAt(0);
    }
    final first = _samples.first;
    final seconds = now.difference(first.$1).inMilliseconds / 1000;
    _speed = seconds > 0 ? (received - first.$2) / seconds : 0;
    emit(_snapshot());
  }

  void finish() {
    final seconds = DateTime.now().difference(_started).inMilliseconds / 1000;
    _speed = seconds > 0 ? received / seconds : 0;
    emit(_snapshot(done: true));
  }

  void fail() => emit(_snapshot(done: true, failed: true));

  DownloadProgress _snapshot({bool done = false, bool failed = false}) =>
      DownloadProgress(
        label: label,
        received: received,
        total: total,
        bytesPerSecond: _speed,
        elapsed: DateTime.now().difference(_started),
        done: done,
        failed: failed,
      );
}
