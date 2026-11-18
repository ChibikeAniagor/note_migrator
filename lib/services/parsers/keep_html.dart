import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/note.dart';

const _colorClasses = {
  'default',
  'red',
  'coral',
  'orange',
  'peach',
  'yellow',
  'sand',
  'green',
  'mint',
  'teal',
  'sage',
  'blue',
  'fog',
  'cerulean',
  'storm',
  'purple',
  'dusk',
  'pink',
  'blossom',
  'brown',
  'clay',
  'gray',
  'grey',
  'chalk',
  'white',
};

/// Reads one Keep Takeout HTML note. Returns null when the file has no note.
UniversalNote? parseKeepHtml({
  required String html,
  required String fileName,
  required String id,
}) {
  final document = html_parser.parse(html);
  final noteElement = document.querySelector('.note');
  final title = _readTitle(document);
  final items = _readChecklist(document);
  final content = _withoutLeadingTitle(_readProse(document), title);
  if (title.isEmpty && content.isEmpty && items.isEmpty) return null;

  final classes =
      noteElement?.classes.map((c) => c.toLowerCase()).toSet() ?? {};
  String? color;
  for (final name in classes) {
    if (_colorClasses.contains(name) && name != 'default' && name != 'white') {
      color = name.toUpperCase();
    }
  }

  return UniversalNote(
    id: id,
    title: title,
    content: content,
    createdAt: null,
    modifiedAt: null,
    tags: _readLabels(document),
    color: color,
    isPinned: _hasFlag(document, classes, 'pinned'),
    isArchived: _hasFlag(document, classes, 'archived'),
    isTrashed: _hasFlag(document, classes, 'trashed'),
    attachments: const [],
    type: items.isEmpty ? NoteType.text : NoteType.checklist,
    checklistItems: items,
    links: _readLinks(document),
    sourceFileName: fileName,
  );
}

String _withoutLeadingTitle(String content, String title) {
  if (title.isEmpty || content.isEmpty) return content;
  if (content == title) return '';
  if (content.startsWith('$title\n')) {
    return content.substring(title.length).trim();
  }
  return content;
}

String _readTitle(Document document) {
  for (final selector in ['.heading', '.title', 'h1']) {
    final text = document.querySelector(selector)?.text.trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  final fromTag = document.querySelector('title')?.text.trim() ?? '';
  if (fromTag.isEmpty || fromTag.toLowerCase() == 'google keep') return '';
  return fromTag;
}

List<ChecklistItem> _readChecklist(Document document) {
  var elements = document.querySelectorAll('.listitem');
  if (elements.isEmpty) elements = document.querySelectorAll('li');
  final items = <ChecklistItem>[];
  for (final element in elements) {
    final textElement = element.querySelector('.text');
    final text = (textElement == null ? element.text : textElement.text).trim();
    final cleaned = text.replaceAll(RegExp(r'^[☐☑✓✔\[\]xX ]+'), '').trim();
    if (cleaned.isEmpty && text.isEmpty) continue;
    items.add(
      ChecklistItem(
        text: cleaned.isEmpty ? text : cleaned,
        isChecked: _isChecked(element),
      ),
    );
  }
  return items;
}

bool _isChecked(Element element) {
  final classes = element.className.toLowerCase();
  if (classes.contains('checked')) return true;
  final input = element.querySelector('input');
  if (input != null &&
      (input.attributes.containsKey('checked') ||
          input.attributes['aria-checked'] == 'true')) {
    return true;
  }
  final bullet = element.querySelector('.bullet')?.text ?? '';
  return bullet.contains('☑') ||
      bullet.contains('✓') ||
      bullet.contains('✔') ||
      bullet.toLowerCase().contains('[x]');
}

String _readProse(Document document) {
  final content = document.querySelector('.content');
  if (content == null) {
    final body = document.body;
    if (body == null) return '';
    return _inlineText(body);
  }
  final buffer = StringBuffer();
  for (final node in content.nodes) {
    if (node is Element && _isListContainer(node)) continue;
    final text = _inlineText(node);
    if (text.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.write(text);
  }
  return buffer.toString().trim();
}

bool _isListContainer(Element element) {
  final name = element.localName ?? '';
  final classes = element.className.toLowerCase();
  if (name == 'ul' || name == 'ol' || classes.contains('listitem')) return true;
  if (classes.contains('list')) return true;
  return element.querySelector('.listitem, li') != null &&
      (classes.contains('list') || name == 'ul' || name == 'ol');
}

List<String> _readLabels(Document document) {
  var elements = document.querySelectorAll('.label-name');
  if (elements.isEmpty) {
    elements = document.querySelectorAll('.labels .label, .chip');
  }
  final labels = <String>[];
  for (final element in elements) {
    final text = element.text.trim();
    if (text.isEmpty || labels.contains(text)) continue;
    if (text.toLowerCase() == 'archived' || text.toLowerCase() == 'pinned') {
      continue;
    }
    labels.add(text);
  }
  return labels;
}

bool _hasFlag(Document document, Set<String> classes, String flag) {
  if (classes.any((name) => name.contains(flag))) return true;
  for (final element in document.querySelectorAll('[class]')) {
    if (element.className.toLowerCase().contains(flag)) return true;
  }
  return false;
}

List<String> _readLinks(Document document) {
  final links = <String>[];
  for (final anchor in document.querySelectorAll('a')) {
    final href = anchor.attributes['href']?.trim() ?? '';
    if (href.isEmpty || links.contains(href)) continue;
    links.add(href);
  }
  return links;
}

String _inlineText(Node node) {
  final buffer = StringBuffer();
  void walk(Node current) {
    if (current is Text) {
      buffer.write(current.text);
      return;
    }
    if (current is! Element) return;
    final name = current.localName;
    if (name == 'script' || name == 'style') return;
    if (name == 'br') {
      buffer.write('\n');
      return;
    }
    final block = name == 'p' || name == 'div' || name == 'li' || name == 'h1';
    if (block && buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
      buffer.write('\n');
    }
    for (final child in current.nodes) {
      walk(child);
    }
  }

  walk(node);
  return buffer
      .toString()
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
