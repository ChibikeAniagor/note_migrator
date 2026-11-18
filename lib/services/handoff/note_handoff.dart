import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/note_app.dart';
import '../parsers/note_parser.dart';

/// What happened when the app tried to open Keep or Mi Notes.
enum HandoffStatus { opened, missing, refused, failed, unsupported }

/// Text or files another app shared into Note Migrator.
class IncomingShare {
  const IncomingShare({
    required this.files,
    this.sender,
    this.error,
  });

  final List<ImportedBytes> files;
  final NoteAppId? sender;
  final String? error;
}

/// Opens the installed note app, and collects notes shared into this one.
///
/// Direct open is Android-only. Other platforms use the share sheet.
class NoteHandoff {
  static const _channel = MethodChannel('note_migrator/handoff');

  static Future<HandoffStatus> openNote({
    required NoteAppId target,
    required String title,
    required String text,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return HandoffStatus.unsupported;
    try {
      final status = await _channel.invokeMethod<String>('openNote', {
        'target': target.name,
        'title': title,
        'text': text,
      });
      return switch (status) {
        'opened' => HandoffStatus.opened,
        'missing' => HandoffStatus.missing,
        'refused' => HandoffStatus.refused,
        _ => HandoffStatus.failed,
      };
    } on MissingPluginException {
      return HandoffStatus.unsupported;
    } catch (_) {
      return HandoffStatus.failed;
    }
  }

  /// Returns the share waiting from another app, then forgets it.
  static Future<IncomingShare?> takeIncoming() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>('takeShared');
      if (raw is! Map) return null;
      final error = raw['error'];
      final sender = _sender(raw['sender']);
      final items = raw['items'];
      final files = <ImportedBytes>[];
      if (items is List) {
        for (final item in items) {
          if (item is! Map) continue;
          final name = item['name'] is String
              ? item['name'] as String
              : 'shared-note.txt';
          final bytes = item['bytes'];
          if (bytes is Uint8List) {
            files.add(ImportedBytes(name: name, bytes: bytes));
            continue;
          }
          if (bytes is List<int>) {
            files.add(ImportedBytes(name: name, bytes: bytes));
            continue;
          }
          final text = item['text'];
          if (text is String && text.trim().isNotEmpty) {
            files.add(
              ImportedBytes(name: _nameForText(name, text), bytes: utf8.encode(text)),
            );
          }
        }
      }
      if (files.isEmpty && error is! String) return null;
      return IncomingShare(
        files: files,
        sender: sender,
        error: error is String ? error : null,
      );
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

NoteAppId? _sender(Object? package) {
  return switch (package) {
    'com.google.android.keep' => NoteAppId.googleKeep,
    'com.miui.notes' => NoteAppId.miNotes,
    _ => null,
  };
}

String _nameForText(String name, String text) {
  if (name.toLowerCase().endsWith('.json') || name.toLowerCase().endsWith('.txt')) {
    return name;
  }
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return 'shared-note.json';
  }
  return 'shared-note.txt';
}
