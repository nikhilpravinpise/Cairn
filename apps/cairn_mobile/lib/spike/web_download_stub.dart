/// Non-web stub. Download-as-file is implemented in `web_download_web.dart`.
library;

void downloadJson(String json, String filename) {
  // On non-web targets we rely on the Clipboard copy button. Write to logs for
  // the record so the operator can still retrieve it.
  // ignore: avoid_print
  print('[downloadJson] not supported on this platform. filename=$filename '
      'length=${json.length} (use the Copy button instead).');
}
