import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:descarga_videos/main.dart';

void main() {
  testWidgets('Downloader UI smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DownloaderApp());

    // Verify that the title is present.
    expect(find.text('YT Downloader Fast'), findsOneWidget);
    
    // Verify that the download button is present.
    expect(find.text('Descargar'), findsOneWidget);
  });
}
