/// A note app the migrator knows about.
///
/// Google Keep and Mi Notes can be either end of a move. The others are
/// listed so the source screen can show what this version does not do yet.
enum NoteAppId {
  googleKeep(
    'Google Keep',
    'Takeout zip, JSON, or a shared note',
    true,
    targetDetail: 'Opens with the note filled in',
  ),
  miNotes(
    'Mi Notes',
    'Shared note, text file, or JSON',
    true,
    targetDetail: 'Opens with the note filled in',
  ),
  appleNotes('Apple Notes', 'Not in this version', false),
  notion('Notion', 'Not in this version', false),
  evernote('Evernote', 'Not in this version', false);

  const NoteAppId(
    this.label,
    this.detail,
    this.available, {
    this.targetDetail,
  });

  final String label;
  final String detail;
  final bool available;

  /// What happens when this app is the destination.
  final String? targetDetail;

  String get handoffDetail => targetDetail ?? detail;

  NoteAppId get opposite => switch (this) {
    NoteAppId.googleKeep => NoteAppId.miNotes,
    NoteAppId.miNotes => NoteAppId.googleKeep,
    _ => NoteAppId.miNotes,
  };
}
