import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_xlog/flutter_xlog.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XLogExampleApp());
}

class XLogExampleApp extends StatelessWidget {
  const XLogExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_xlog example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const XLogExamplePage(),
    );
  }
}

class XLogExamplePage extends StatefulWidget {
  const XLogExamplePage({super.key});

  @override
  State<XLogExamplePage> createState() => _XLogExamplePageState();
}

class _XLogExamplePageState extends State<XLogExamplePage> {
  String _status = 'Not initialized';
  String _logDir = '';
  bool _initialized = false;

  Future<void> _initXLog() async {
    await _runAction(() async {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = '${directory.path}/xlog/logs';
      final cacheDir = '${directory.path}/xlog/cache';

      FlutterXLog.instance.init(
        logDir: logDir,
        cacheDir: cacheDir,
        prefixName: 'flutter_xlog_example',
        level: XLogLevel.debug,
        mode: XLogMode.async,
        cacheDays: 3,
        consoleLogOpen: true,
      );

      setState(() {
        _initialized = true;
        _logDir = logDir;
        _status = 'Initialized';
      });
    });
  }

  void _writeSampleLogs() {
    _runAction(() {
      FlutterXLog.instance.d('Example', 'debug log from flutter_xlog example');
      FlutterXLog.instance.i('Example', 'info log from flutter_xlog example');
      FlutterXLog.instance.w('Example', 'warn log from flutter_xlog example');
      FlutterXLog.instance.e('Example', 'error log from flutter_xlog example');

      setState(() {
        _status = 'Sample logs written';
      });
    });
  }

  void _flushLogs() {
    _runAction(() {
      FlutterXLog.instance.flush(sync: true);
      setState(() {
        _status = 'Logs flushed';
      });
    });
  }

  void _closeXLog() {
    _runAction(() {
      FlutterXLog.instance.close();
      setState(() {
        _initialized = false;
        _status = 'Closed';
      });
    });
  }

  @override
  void dispose() {
    if (_initialized) {
      FlutterXLog.instance.close();
    }
    super.dispose();
  }

  Future<void> _runAction(FutureOr<void> Function() action) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'flutter_xlog example',
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Error: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_xlog example')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Status: $_status'),
            const SizedBox(height: 8),
            Text(_logDir.isEmpty ? 'Log directory: not created yet' : 'Log directory: $_logDir'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _initialized ? null : _initXLog,
              child: const Text('Initialize xlog'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _initialized ? _writeSampleLogs : null,
              child: const Text('Write sample logs'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _initialized ? _flushLogs : null,
              child: const Text('Flush logs'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _initialized ? _closeXLog : null,
              child: const Text('Close xlog'),
            ),
          ],
        ),
      ),
    );
  }
}
