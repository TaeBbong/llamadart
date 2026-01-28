import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// A Helper class to download models.
class ModelDownloader {
  final String _cacheDir;

  /// Creates a [ModelDownloader] with an optional [cacheDir].
  ModelDownloader([String? cacheDir])
      : _cacheDir = cacheDir ?? path.join(Directory.current.path, 'tmp');

  /// Downloads a model from [url] to the cache directory.
  /// Returns the [File] object of the downloaded model.
  Future<File> downloadModel(String url, {String? fileName}) async {
    final name = fileName ?? url.split('/').last;
    final file = File(path.join(_cacheDir, name));

    // Ensure cache directory exists
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    if (file.existsSync()) {
      print('Model already exists at: ${file.path}');
      return file;
    }

    print('Downloading model from $url...');
    print('Target: ${file.path}');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to download model: ${response.statusCode} ${response.reasonPhrase}');
      }

      final contentLength = response.contentLength ?? 0;
      var downloadedBytes = 0;
      final sink = file.openWrite();

      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          _printProgress(downloadedBytes, contentLength);
        },
        onDone: () async {
          await sink.close();
          print('\nDownload complete!');
        },
        onError: (e) {
          sink.close();
          file.deleteSync(); // Clean up partial file
          throw e;
        },
      ).asFuture();

      return file;
    } finally {
      client.close();
    }
  }

  void _printProgress(int current, int total) {
    if (total == 0) {
      stdout.write('\rDownloaded: ${_formatBytes(current)}');
    } else {
      final percentage = (current / total * 100).toStringAsFixed(1);
      stdout.write(
          '\rDownloaded: ${_formatBytes(current)} / ${_formatBytes(total)} ($percentage%)');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
