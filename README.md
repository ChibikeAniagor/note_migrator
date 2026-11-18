# Note Migrator

Move notes between Google Keep and Mi Notes on this phone.

Neither app lets another app write its database. Note Migrator reads the notes, then opens the other app with each note filled in. You save it there. That one tap is the confirmation those apps require.

## Keep to Mi Notes

1. Share a Keep note into Note Migrator, or open a Google Takeout zip (Keep only) for the whole account.
2. Uncheck notes you want to leave behind. Trashed notes start unselected.
3. Tap **Open in Mi Notes**. Save the note, come back, and the next one is ready.

Takeout is still how a whole Keep account comes out. Keep does not give other apps a way to read the account directly, and this app never signs in to Google.

## Mi Notes to Keep

1. In Mi Notes, open a note, tap Share, and choose Note Migrator. Repeat for each note. Or open a text or JSON file you already saved.
2. Review the list.
3. Tap **Open in Keep**. Save the note, come back, and the next one is ready.

## What changes

Colors, labels, and pin status are written into the note so they are not dropped silently. Checklists become `[ ]` and `[x]` lines. Images are named and not copied. You see that list before anything is sent.

If Keep or Mi Notes is not installed, share or copy the text instead. A JSON backup can be opened in Note Migrator again. Keep and Mi Notes cannot import that file by themselves.

Opening the other app directly works on Android. On iPhone, use Share and pick the note app.

## Run

```bash
flutter pub get
flutter test
flutter run
```

On the import screen, "Preview with sample notes" walks the whole flow without an export file. If you leave the review screen, "Review N notes" brings those notes back. Search text is kept.

A release APK for sideloading is `build/app/outputs/flutter-apk/app-release.apk` after `flutter build apk --release`. That build is signed with the debug key so you can install it yourself. Publishing on the Play Store needs your own application id and upload key. The id in this project is still `com.example.note_migrator`.
