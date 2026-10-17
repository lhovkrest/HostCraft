import 'dart:math' as math;

/// A snapshot of one running transfer, shown in the console.
class DownloadProgress {
  const DownloadProgress({
    required this.label,
    this.received = 0,
    this.total,
    this.bytesPerSecond = 0,
    this.elapsed = Duration.zero,
    this.done = false,
    this.failed = false,
    this.isStep = false,
  });

  /// A phase with no byte counts, such as extracting an archive.
  const DownloadProgress.step(String label) : this(label: label, isStep: true);

  final String label;
  final int received;

  /// Size of the whole file, or null when the server did not announce it.
  final int? total;

  /// Recent transfer speed. On the final snapshot this is the average.
  final double bytesPerSecond;
  final Duration elapsed;
  final bool done;
  final bool failed;
  final bool isStep;

  /// 0..1, or null when the size is unknown.
  double? get fraction {
    final size = total;
    if (size == null || size <= 0) return null;
    return math.min(1.0, math.max(0.0, received / size));
  }

  /// Estimated time left, or null when it cannot be worked out yet.
  Duration? get eta {
    final size = total;
    if (size == null || bytesPerSecond < 1) return null;
    final remaining = size - received;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / bytesPerSecond).ceil());
  }
}

String formatBytes(num bytes) {
  if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${bytes.round()} B';
}

String formatSpeed(double bytesPerSecond) => bytesPerSecond >= 1048576
    ? '${(bytesPerSecond / 1048576).toStringAsFixed(1)} MB/s'
    : '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';

String formatDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${math.max(1, d.inSeconds)}s';
}
