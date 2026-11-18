import 'package:flutter/material.dart';

/// Keep color names from Takeout, including the older word set
/// (`CORAL`, `SAND`, and so on).
const _swatches = <String, Color>{
  'RED': Color(0xFFF28B82),
  'CORAL': Color(0xFFF28B82),
  'ORANGE': Color(0xFFFBBC04),
  'PEACH': Color(0xFFFBBC04),
  'YELLOW': Color(0xFFFFF475),
  'SAND': Color(0xFFFFF475),
  'GREEN': Color(0xFFCCFF90),
  'MINT': Color(0xFFCCFF90),
  'TEAL': Color(0xFFA7FFEB),
  'SAGE': Color(0xFFA7FFEB),
  'BLUE': Color(0xFFCBF0F8),
  'FOG': Color(0xFFCBF0F8),
  'CERULEAN': Color(0xFFAECBFA),
  'STORM': Color(0xFFAECBFA),
  'PURPLE': Color(0xFFD7AEFB),
  'DUSK': Color(0xFFD7AEFB),
  'PINK': Color(0xFFFDCFE8),
  'BLOSSOM': Color(0xFFFDCFE8),
  'BROWN': Color(0xFFE6C9A8),
  'CLAY': Color(0xFFE6C9A8),
  'GRAY': Color(0xFFE8EAED),
  'GREY': Color(0xFFE8EAED),
  'CHALK': Color(0xFFE8EAED),
};

const _names = <String, String>{
  'RED': 'Red',
  'CORAL': 'Red',
  'ORANGE': 'Orange',
  'PEACH': 'Orange',
  'YELLOW': 'Yellow',
  'SAND': 'Yellow',
  'GREEN': 'Green',
  'MINT': 'Green',
  'TEAL': 'Teal',
  'SAGE': 'Teal',
  'BLUE': 'Blue',
  'FOG': 'Blue',
  'CERULEAN': 'Cerulean',
  'STORM': 'Cerulean',
  'PURPLE': 'Purple',
  'DUSK': 'Purple',
  'PINK': 'Pink',
  'BLOSSOM': 'Pink',
  'BROWN': 'Brown',
  'CLAY': 'Brown',
  'GRAY': 'Gray',
  'GREY': 'Gray',
  'CHALK': 'Gray',
};

/// Swatch for a note card. Default notes get a neutral bar.
Color keepSwatch(String? color) {
  if (color == null) return const Color(0xFFE4DDD2);
  return _swatches[color.toUpperCase()] ?? const Color(0xFFE4DDD2);
}

/// True for a Keep swatch name such as `YELLOW` or `Yellow`.
bool isKnownKeepColor(String? color) {
  if (color == null) return false;
  return _swatches.containsKey(color.toUpperCase());
}

/// Human color name written into the exported text. Null for the default.
String? keepColorName(String? color) {
  if (color == null) return null;
  final key = color.toUpperCase();
  if (key.isEmpty || key == 'DEFAULT' || key == 'WHITE' || key == 'NONE') {
    return null;
  }
  return _names[key] ?? _titleCase(key);
}

String _titleCase(String value) {
  final lower = value.toLowerCase();
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}
