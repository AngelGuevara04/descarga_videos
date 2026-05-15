import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';

void main() => runApp(const DownloaderApp());

class DownloaderApp extends StatelessWidget {
  const DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT Downloader Fast',
      theme: ThemeData.dark(),
      home: const DownloaderScreen(),
    );
  }
}

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();

  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = '';
  String _selectedFormat = 'MP4';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        await Permission.manageExternalStorage.request();
      }
    }
  }

  String _formatBytes(num bytes) {
    if (bytes == 0) return "0 MB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  Future<void> _downloadMedia() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusMessage = 'Obteniendo información...';
    });

    try {
      var video = await _yt.videos.get(url);
      var manifest = await _yt.videos.streamsClient.getManifest(url);

      // EL TRUCO: Siempre descargamos el video (muxed) porque sabemos que no lo bloquean
      StreamInfo streamInfo = manifest.muxed.withHighestBitrate();

      Directory tempDir = await getTemporaryDirectory();
      String safeTitle = video.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').replaceAll(' ', '_');

      // Archivo temporal base (siempre será mp4 al inicio)
      File tempVideoFile = File('${tempDir.path}/$safeTitle.mp4');

      if (await tempVideoFile.exists()) await tempVideoFile.delete();

      var stream = _yt.videos.streamsClient.get(streamInfo);
      var fileStream = tempVideoFile.openWrite(mode: FileMode.write);

      var totalBytes = streamInfo.size.totalBytes;
      var receivedBytes = 0;

      setState(() {
        _statusMessage = 'Descargando datos base: 0 MB / ${_formatBytes(totalBytes)} (0%)';
      });

      await for (var data in stream) {
        receivedBytes += data.length;
        fileStream.add(data);

        double currentProgress = receivedBytes / totalBytes;
        if (currentProgress - _progress > 0.01 || currentProgress == 1.0) {
          setState(() {
            _progress = currentProgress;
            _statusMessage = 'Descargando: ${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)} (${(_progress * 100).toStringAsFixed(0)}%)';
          });
        }
      }

      await fileStream.flush();
      await fileStream.close();

      String fileToSavePath = tempVideoFile.path;
      String finalExtension = '.mp4';

      // MAGIA DE FFmpeg: Si pidió MP3, extraemos el audio
      if (_selectedFormat == 'MP3') {
        setState(() {
          _statusMessage = 'Convirtiendo a MP3 (Extrayendo audio)...';
          _progress = -1.0; // Pone la barra en modo de "Carga infinita"
        });

        File tempAudioFile = File('${tempDir.path}/$safeTitle.mp3');
        if (await tempAudioFile.exists()) await tempAudioFile.delete();

        // Comando para quitar video (-vn) y guardar como audio de alta calidad
        String command = '-y -i "${tempVideoFile.path}" -vn -b:a 192k "${tempAudioFile.path}"';

        var session = await FFmpegKit.execute(command);
        var returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          fileToSavePath = tempAudioFile.path;
          finalExtension = '.mp3';
        } else {
          throw Exception('Falló la conversión a MP3 con FFmpeg.');
        }
      }

      setState(() {
        _progress = 1.0;
        _statusMessage = 'Guardando en tus descargas...';
      });

      final params = SaveFileDialogParams(
        sourceFilePath: fileToSavePath,
        fileName: '$safeTitle$finalExtension',
      );

      final finalPath = await FlutterFileDialog.saveFile(params: params);

      if (finalPath != null) {
        setState(() => _statusMessage = '¡Éxito! Archivo guardado.');
      } else {
        setState(() => _statusMessage = 'Descarga finalizada, guardado cancelado.');
      }

      // Limpieza: Borramos los archivos temporales para no llenar la memoria oculta
      if (await tempVideoFile.exists()) await tempVideoFile.delete();
      File audioTemp = File('${tempDir.path}/$safeTitle.mp3');
      if (await audioTemp.exists()) await audioTemp.delete();

      setState(() => _isDownloading = false);

    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
        _isDownloading = false;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('YT Downloader Fast')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL del video de YouTube',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButton<String>(
              value: _selectedFormat,
              items: <String>['MP4', 'MP3'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() => _selectedFormat = newValue!);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isDownloading ? null : _downloadMedia,
              child: const Text('Descargar'),
            ),
            const SizedBox(height: 30),
            if (_isDownloading)
              LinearProgressIndicator(value: _progress >= 0 ? _progress : null),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
