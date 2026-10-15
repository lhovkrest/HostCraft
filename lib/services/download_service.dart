import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class DownloadService {
  DownloadService({this.onProgress, this.contact = ''});
  final void Function(String label, double? progress)? onProgress;
  // Set your own contact URL before distributing a Paper-enabled build.
  final String contact;
  Map<String, String> headers(String url) => {
    'User-Agent':
        'HostCraft/0.1${contact.isEmpty || !Uri.parse(url).host.endsWith('papermc.io') ? '' : ' ($contact)'}',
  };
  Future<dynamic> json(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: headers(url))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode} from ${Uri.parse(url).host}',
      );
    }
    return jsonDecode(response.body);
  }

  Future<void> file(
    String url,
    File target, {
    String? checksum,
    bool useSha1 = false,
    String label = 'Downloading',
  }) async {
    if (Uri.parse(url).scheme != 'https') {
      throw ArgumentError('Downloads must use HTTPS');
    }
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll(headers(url));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} downloading $label');
      }
      sink = part.openWrite();
      var received = 0;
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 90),
      )) {
        sink.add(bytes);
        received += bytes.length;
        if (DateTime.now().difference(last).inMilliseconds > 200) {
          onProgress?.call(
            label,
            response.contentLength == null
                ? null
                : received / response.contentLength!,
          );
          last = DateTime.now();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (response.contentLength != null &&
          received != response.contentLength) {
        throw const HttpException('Incomplete download');
      }
      if (checksum != null) {
        final actual = await (useSha1 ? sha1 : sha256)
            .bind(part.openRead())
            .first;
        if (actual.toString().toLowerCase() != checksum.toLowerCase()) {
          throw const FormatException('Download checksum mismatch');
        }
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      onProgress?.call(label, 1);
    } finally {
      await sink?.close();
      client.close();
      if (await part.exists()) await part.delete();
    }
  }
}
