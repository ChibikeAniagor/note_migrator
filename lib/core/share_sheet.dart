import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/export_format.dart';

/// Rect the iPad share popover needs. Other platforms ignore it.
Rect shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox &&
      box.hasSize &&
      box.size.width > 0 &&
      box.size.height > 0) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final size = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 2,
    height: 2,
  );
}

Future<void> shareNoteText(
  BuildContext context, {
  required String title,
  required String text,
}) async {
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: title,
        sharePositionOrigin: shareOrigin(context),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      _snack(context, 'Could not open the share sheet.');
    }
  }
}

Future<void> shareExportFile(
  BuildContext context,
  ExportPayload payload,
) async {
  try {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${payload.fileName}');
    await file.writeAsBytes(payload.bytes, flush: true);
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path, mimeType: payload.mimeType, name: payload.fileName),
        ],
        subject: payload.fileName,
        sharePositionOrigin: shareOrigin(context),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      _snack(context, 'Could not share ${payload.fileName}.');
    }
  }
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) _snack(context, 'Copied');
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
