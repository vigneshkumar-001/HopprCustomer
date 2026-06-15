import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:share_plus/share_plus.dart';

class AppLogger {
  // On-device log file so logs from a REAL (untethered) ride can be captured
  // and shared afterwards. Lives in the app's temp/cache dir.
  static final File _logFile = File(
    '${Directory.systemTemp.path}/hoppr_ride_log.txt',
  );
  static final _FileLogOutput _fileOutput = _FileLogOutput(_logFile);

  static final Logger log = Logger(
    filter: kDebugMode ? DevelopmentFilter() : ProductionFilter(),
    printer: _BluePrinter(
      PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        lineLength: 120,
        colors: true,
        printEmojis: false,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    ),
    // Console (as before) + the on-device file.
    output: MultiOutput([ConsoleOutput(), _fileOutput]),
  );

  /// Opens the system share sheet with the captured log file (WhatsApp / email).
  static Future<void> shareLogs() async {
    try {
      await _fileOutput.flush();
      if (await _logFile.exists() && await _logFile.length() > 0) {
        await SharePlus.instance.share(
          ShareParams(
            text: 'Hoppr ride logs',
            files: [XFile(_logFile.path)],
          ),
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(text: 'No Hoppr logs captured yet.'),
        );
      }
    } catch (_) {}
  }

  /// Clears the captured log file (tap before starting a fresh test ride).
  static Future<void> clearLogs() async {
    await _fileOutput.reset();
  }
}

/// Appends each log line to [_file] (ANSI colour codes stripped).
class _FileLogOutput extends LogOutput {
  _FileLogOutput(this._file) {
    _open();
  }

  final File _file;
  IOSink? _sink;
  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;]*m');

  void _open() {
    try {
      _sink = _file.openWrite(mode: FileMode.writeOnlyAppend);
    } catch (_) {
      _sink = null;
    }
  }

  @override
  void output(OutputEvent event) {
    final s = _sink;
    if (s == null) return;
    try {
      for (final line in event.lines) {
        s.writeln(line.replaceAll(_ansi, ''));
      }
    } catch (_) {}
  }

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  Future<void> reset() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    try {
      if (await _file.exists()) await _file.writeAsString('');
    } catch (_) {}
    _open();
  }

  @override
  Future<void> destroy() async {
    try {
      await _sink?.close();
    } catch (_) {}
  }
}

class _BluePrinter extends LogPrinter {
  _BluePrinter(this._inner);

  final LogPrinter _inner;

  static const String _blue = '\x1B[34m';
  static const String _reset = '\x1B[0m';

  @override
  List<String> log(LogEvent event) {
    final lines = _inner.log(event);
    if (!kDebugMode) return lines;
    return lines.map((l) => '$_blue$l$_reset').toList(growable: false);
  }
}
