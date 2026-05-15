import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Instancia global para las notificaciones
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización de las notificaciones para Android usando el logo de tu app
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

  // Versión estable sin etiquetas
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const DownloaderApp());
}

class DownloaderApp extends StatelessWidget {
  const DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApexDL',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark
        ),
      ),
      home: const DownloaderScreen(),
    );
  }
}

class DownloadTask {
  String id = UniqueKey().toString();
  // Un ID numérico único para que Android separe las notificaciones de cada descarga
  int notifId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
  String url;
  String title = "Obteniendo información...";
  double progress = 0.0;
  String status = "Iniciando...";
  bool isDownloading = true;
  bool hasError = false;
  String format;

  DownloadTask({required this.url, required this.format});
}

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();

  String _selectedFormat = 'MP3';
  late StreamSubscription _intentSubscription;

  String? _saveDirectoryMp4;
  String? _saveDirectoryMp3;
  bool _isLoadingPrefs = true;

  final List<DownloadTask> _activeDownloads = [];

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // Pedir permisos de notificaciones al iniciar
    if (Platform.isAndroid) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    final prefs = await SharedPreferences.getInstance();

    if (mounted) {
      setState(() {
        _saveDirectoryMp4 = prefs.getString('save_directory_mp4');
        _saveDirectoryMp3 = prefs.getString('save_directory_mp3');
        _isLoadingPrefs = false;
      });
    }

    _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) _processSharedText(value.first.path);
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) _processSharedText(value.first.path);
    });
  }

  void _processSharedText(String text) {
    RegExp regExp = RegExp(r"(https?://[^\s]+)");
    var match = regExp.firstMatch(text);
    if (match != null) {
      if (_saveDirectoryMp4 == null || _saveDirectoryMp3 == null) {
        setState(() => _urlController.text = match.group(0)!);
      } else {
        _startNewDownload(match.group(0)!);
      }
    }
  }

  Future<void> _pickDirectory(String format) async {
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }

    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null) {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        if (format == 'MP4') {
          prefs.setString('save_directory_mp4', selectedDirectory);
          _saveDirectoryMp4 = selectedDirectory;
        } else {
          prefs.setString('save_directory_mp3', selectedDirectory);
          _saveDirectoryMp3 = selectedDirectory;
        }
      });
    }
  }

  String _formatBytes(num bytes) {
    if (bytes == 0) return "0 MB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

// --- MOTOR DE NOTIFICACIONES ---
  Future<void> _showProgressNotification(DownloadTask task, int progressPercent, String body) async {
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'download_channel', // ID interno
      'Descargas Activas', // Nombre público en configuración
      channelDescription: 'Muestra el progreso de tus descargas',
      importance: Importance.low, // Low para que no haga ruido a cada segundo
      priority: Priority.low,
      onlyAlertOnce: true, // Para que no vibre cada vez que avanza el porcentaje
      showProgress: progressPercent >= 0,
      maxProgress: 100,
      progress: progressPercent,
      icon: '@mipmap/ic_launcher',
    );

    NotificationDetails details = NotificationDetails(android: androidDetails);

    // Versión estable posicional
    await flutterLocalNotificationsPlugin.show(
      task.notifId,
      task.title,
      body,
      details,
    );
  }

  Future<void> _showSuccessNotification(DownloadTask task) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'success_channel',
      'Descargas Completadas',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    // Versión estable posicional
    await flutterLocalNotificationsPlugin.show(
      task.notifId,
      '✅ ¡Descarga Completada!',
      task.title,
      details,
    );
  }

  Future<void> _showErrorNotification(DownloadTask task) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'error_channel',
      'Errores de Descarga',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    // Versión estable posicional
    await flutterLocalNotificationsPlugin.show(
      task.notifId,
      '❌ Error en la descarga',
      task.title,
      details,
    );
  }
  // --------------------------------

  void _startNewDownload(String url) {
    if (url.isEmpty || _saveDirectoryMp4 == null || _saveDirectoryMp3 == null) return;

    final newTask = DownloadTask(url: url, format: _selectedFormat);
    setState(() {
      _activeDownloads.insert(0, newTask);
      _urlController.clear();
    });

    // Inicia la notificación en 0%
    _showProgressNotification(newTask, 0, "Iniciando conexión...");
    _processDownloadTask(newTask);
  }

  Future<void> _processDownloadTask(DownloadTask task) async {
    try {
      await _downloadNormalMethod(task);
    } catch (e) {
      _updateTaskState(task, () {
        task.status = 'YouTube bloqueó. Usando servidor de respaldo...';
        task.progress = -1.0;
      });
      _showProgressNotification(task, -1, 'Usando servidor de respaldo...');

      try {
        await _downloadFallbackMethod(task);
      } catch (fallbackError) {
        _updateTaskState(task, () {
          task.status = 'Error: No se pudo descargar.';
          task.hasError = true;
          task.isDownloading = false;
        });
        _showErrorNotification(task);
      }
    }
  }

  void _updateTaskState(DownloadTask task, VoidCallback updateCode) {
    if (mounted) setState(updateCode);
  }

  Future<void> _downloadNormalMethod(DownloadTask task) async {
    var video = await _yt.videos.get(task.url);
    _updateTaskState(task, () => task.title = video.title);
    _showProgressNotification(task, 0, "Preparando archivo...");

    var manifest = await _yt.videos.streamsClient.getManifest(task.url);
    StreamInfo streamInfo = manifest.muxed.withHighestBitrate();

    Directory tempDir = await getTemporaryDirectory();
    String safeTitle = video.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').replaceAll(' ', '_');
    File tempVideoFile = File('${tempDir.path}/${task.id}.mp4');

    if (await tempVideoFile.exists()) await tempVideoFile.delete();

    var stream = _yt.videos.streamsClient.get(streamInfo);
    var fileStream = tempVideoFile.openWrite(mode: FileMode.write);
    var totalBytes = streamInfo.size.totalBytes;
    var receivedBytes = 0;

    await for (var data in stream) {
      receivedBytes += data.length;
      fileStream.add(data);
      double currentProgress = receivedBytes / totalBytes;

      if (currentProgress - task.progress > 0.02 || currentProgress == 1.0) {
        _updateTaskState(task, () {
          task.progress = currentProgress;
          task.status = 'Descargando: ${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)}';
        });
        // Actualiza la barra de la notificación
        _showProgressNotification(task, (currentProgress * 100).toInt(), task.status);
      }
    }

    await fileStream.flush();
    await fileStream.close();

    String fileToSavePath = tempVideoFile.path;
    String finalExtension = '.mp4';

    if (task.format == 'MP3') {
      _updateTaskState(task, () {
        task.status = 'Convirtiendo a MP3...';
        task.progress = -1.0;
      });
      _showProgressNotification(task, -1, "Extrayendo audio de alta calidad...");

      File tempAudioFile = File('${tempDir.path}/${task.id}.mp3');
      if (await tempAudioFile.exists()) await tempAudioFile.delete();

      String command = '-y -i "${tempVideoFile.path}" -vn -b:a 192k "${tempAudioFile.path}"';
      var session = await FFmpegKit.execute(command);
      var returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        fileToSavePath = tempAudioFile.path;
        finalExtension = '.mp3';
      } else {
        throw Exception('FFmpeg falló');
      }
    }

    await _autoSaveToDownloads(task, fileToSavePath, '$safeTitle$finalExtension');

    if (await tempVideoFile.exists()) await tempVideoFile.delete();
    File audioTemp = File('${tempDir.path}/${task.id}.mp3');
    if (await audioTemp.exists()) await audioTemp.delete();
  }

  Future<void> _downloadFallbackMethod(DownloadTask task) async {
    final response = await http.post(
      Uri.parse('https://api.cobalt.tools/api/json'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
      },
      body: jsonEncode({
        'url': task.url,
        'isAudioOnly': task.format == 'MP3',
        'aFormat': 'mp3',
      }),
    );

    if (response.statusCode != 200) throw Exception('API rechazada');

    final json = jsonDecode(response.body);
    final downloadUrl = json['url'];
    if (downloadUrl == null) throw Exception('No link');

    _updateTaskState(task, () {
      task.status = 'Descargando desde servidor de respaldo...';
      task.progress = 0.0;
    });

    var request = http.Request('GET', Uri.parse(downloadUrl));
    var streamedResponse = await request.send();

    var totalBytes = streamedResponse.contentLength ?? 0;
    var receivedBytes = 0;

    Directory tempDir = await getTemporaryDirectory();
    String safeTitle = 'ApexDL_${DateTime.now().millisecondsSinceEpoch}';
    String ext = task.format == 'MP4' ? '.mp4' : '.mp3';
    File tempFile = File('${tempDir.path}/${task.id}$ext');

    var fileStream = tempFile.openWrite(mode: FileMode.write);

    await for (var data in streamedResponse.stream) {
      receivedBytes += data.length;
      fileStream.add(data);

      if (totalBytes > 0) {
        double currentProgress = receivedBytes / totalBytes;
        if (currentProgress - task.progress > 0.02 || currentProgress == 1.0) {
          _updateTaskState(task, () {
            task.progress = currentProgress;
            task.status = 'Respaldo: ${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)}';
          });
          _showProgressNotification(task, (currentProgress * 100).toInt(), task.status);
        }
      } else {
        _updateTaskState(task, () {
          task.progress = -1.0;
          task.status = 'Respaldo: ${_formatBytes(receivedBytes)} descargados...';
        });
        _showProgressNotification(task, -1, task.status);
      }
    }

    await fileStream.flush();
    await fileStream.close();

    _updateTaskState(task, () => task.title = safeTitle);
    await _autoSaveToDownloads(task, tempFile.path, '$safeTitle$ext');

    if (await tempFile.exists()) await tempFile.delete();
  }

  Future<void> _autoSaveToDownloads(DownloadTask task, String tempPath, String fileName) async {
    try {
      String? targetDirectory = task.format == 'MP4' ? _saveDirectoryMp4 : _saveDirectoryMp3;

      if (targetDirectory == null) throw Exception("Ruta no definida");

      String safeFileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      String finalPath = '$targetDirectory/$safeFileName';

      File tempFile = File(tempPath);
      await tempFile.copy(finalPath);

      _updateTaskState(task, () {
        task.status = '¡Guardado en ${targetDirectory.split('/').last}!';
        task.progress = 1.0;
        task.isDownloading = false;
      });

      // Lanza notificación de éxito
      _showSuccessNotification(task);

    } catch (e) {
      _updateTaskState(task, () {
        task.status = 'Error al guardar archivo. Revisa permisos.';
        task.hasError = true;
        task.isDownloading = false;
      });
      _showErrorNotification(task);
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rutas de Descarga', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_library, color: Colors.deepPurpleAccent),
                title: const Text('Carpeta MP4'),
                subtitle: Text(_saveDirectoryMp4 ?? 'No definida', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.edit),
                onTap: () {
                  Navigator.pop(context);
                  _pickDirectory('MP4');
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.library_music, color: Colors.deepPurpleAccent),
                title: const Text('Carpeta MP3'),
                subtitle: Text(_saveDirectoryMp3 ?? 'No definida', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.edit),
                onTap: () {
                  Navigator.pop(context);
                  _pickDirectory('MP3');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cerrar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _intentSubscription.cancel();
    _urlController.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrefs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ApexDL'),
        actions: [
          if (_saveDirectoryMp4 != null && _saveDirectoryMp3 != null)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Ajustes de guardado',
              onPressed: _showSettingsDialog,
            )
        ],
      ),
      body: (_saveDirectoryMp4 == null || _saveDirectoryMp3 == null)
          ? _buildSetupScreen()
          : _buildMainScreen(),
    );
  }

  Widget _buildSetupScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_special, size: 80, color: Colors.deepPurpleAccent),
            const SizedBox(height: 20),
            const Text(
              '¡Bienvenido a ApexDL!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Configura dónde quieres guardar tus archivos para que las descargas sean automáticas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),

            ElevatedButton.icon(
              onPressed: () => _pickDirectory('MP4'),
              icon: const Icon(Icons.video_file),
              label: const Text('Elegir carpeta para Videos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saveDirectoryMp4 == null ? Colors.grey[800] : Colors.green[800],
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            if (_saveDirectoryMp4 != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                child: Text('✔ ${_saveDirectoryMp4!.split('/').last}', style: const TextStyle(color: Colors.green)),
              )
            else
              const SizedBox(height: 28),

            ElevatedButton.icon(
              onPressed: () => _pickDirectory('MP3'),
              icon: const Icon(Icons.audio_file),
              label: const Text('Elegir carpeta para Audios'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saveDirectoryMp3 == null ? Colors.grey[800] : Colors.green[800],
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            if (_saveDirectoryMp3 != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('✔ ${_saveDirectoryMp3!.split('/').last}', style: const TextStyle(color: Colors.green)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainScreen() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Pega tu enlace aquí',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _selectedFormat,
                items: <String>['MP4', 'MP3'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (String? newValue) => setState(() => _selectedFormat = newValue!),
              ),
              const SizedBox(width: 10),
              FloatingActionButton(
                onPressed: () => _startNewDownload(_urlController.text.trim()),
                child: const Icon(Icons.download),
              ),
            ],
          ),
        ),

        const Divider(),

        Expanded(
          child: _activeDownloads.isEmpty
              ? const Center(child: Text('Tus descargas activas aparecerán aquí.'))
              : ListView.builder(
            itemCount: _activeDownloads.length,
            itemBuilder: (context, index) {
              final task = _activeDownloads[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      if (task.isDownloading)
                        LinearProgressIndicator(
                          value: task.progress >= 0 ? task.progress : null,
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              task.status,
                              style: TextStyle(
                                color: task.hasError
                                    ? Colors.redAccent
                                    : (task.isDownloading ? Colors.grey : Colors.green),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            task.format,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}