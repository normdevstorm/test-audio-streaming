import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          // This is the theme of your application.
          //
          // TRY THIS: Try running your application with "flutter run". You'll see
          // the application has a purple toolbar. Then, without quitting the app,
          // try changing the seedColor in the colorScheme below to Colors.green
          // and then invoke "hot reload" (save your changes or press the "hot
          // reload" button in a Flutter-supported IDE, or press "r" if you used
          // the command line to start the app).
          //
          // Notice that the counter didn't reset back to zero; the application
          // state is not lost during the reload. To reset the state, use hot
          // restart instead.
          //
          // This works for code too, not just values: Most code changes can be
          // tested with just a hot reload.
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: AudioStreamingScreen());
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

class AudioStreamingService {
  final String serverHost;
  final int serverPort;
  final AudioPlayer _audioPlayer = AudioPlayer();

  Socket? _tcpSocket;

  AudioRecorder? _audioRecorder;
  StreamSubscription? _audioSubscription;
  bool _isInitialized = false;
  final bool _isRecording = false;

  AudioStreamingService({
    required this.serverHost,
    required this.serverPort,
  });

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      if (!await _requestPermissions()) {
        throw 'Microphone permission denied';
      }
      final String connectMessage = 'APPLICATION';

      _audioRecorder = AudioRecorder();

      _tcpSocket = await Socket.connect(serverHost, serverPort);
      _tcpSocket?.add(connectMessage.codeUnits);
      _isInitialized = true;
      _tcpSocket?.listen(
        (data) => print('Received: ${data.length} bytes'),
        onError: (error) => print('TCP Error: $error'),
        onDone: () => print('TCP connection closed'),
      );
      return _isInitialized;
    } catch (e) {
      print('Initialization Error: $e');
      return false;
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.microphone.request();
      return status == PermissionStatus.granted;
    }
    return true;
  }

  Future<void> startStreaming() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return;
    }

    try {
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      );

      final audioStream = await _audioRecorder?.startStream(config);

      List<int> buffer = [];

      _audioSubscription = audioStream?.listen(
        (data) {
          buffer.addAll(data);
          while (buffer.length >= 4096) {
            final chunk = Uint8List.fromList(buffer.take(4096).toList());
            _sendAudioData(chunk);
            buffer = buffer.skip(4096).toList();
          }
        },
        onError: (error) => print('Audio Stream Error: $error'),
      );
    } catch (e) {
      print('Start Streaming Error: $e');
    }
  }

  void _sendAudioData(Uint8List audioData) async {
    try {
      _tcpSocket?.add(audioData);
      print('Sent ${audioData.toString()} bytes via TCP');
    } catch (e) {
      print('Send Audio Data Error: $e');
    }
  }

  Future<void> stopStreaming() async {
    try {
      await _audioSubscription?.cancel();
      await _audioRecorder?.stop();
    } catch (e) {
      print('Stop Streaming Error: $e');
    }
  }

  void dispose() {
    _audioSubscription?.cancel();
    _audioRecorder?.dispose();
    _tcpSocket?.close();
    _isInitialized = false;
  }
}

class AudioStreamingScreen extends StatefulWidget {
  const AudioStreamingScreen({super.key});

  @override
  State<AudioStreamingScreen> createState() => _AudioStreamingScreenState();
}

class _AudioStreamingScreenState extends State<AudioStreamingScreen> {
  late AudioStreamingService _audioService;
  bool _isStreaming = false;
  bool _isInitialized = false;
  String? _recordedFilePath;
  bool _isRecording = false;
  final _audioPlayer = AudioPlayer();
  final _audioRecorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    _audioService = AudioStreamingService(
      serverHost: '127.0.0.1', // Replace with your server IP
      serverPort: 9876, // Replace with your server port
    );
    _initializeService();
  }

  Future<void> _startRecording() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}\\audio.wav';

    await _audioRecorder.start(
        const RecordConfig(
            encoder: AudioEncoder.pcm16bits, sampleRate: 44100, numChannels: 1),
        path: path);
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await _audioRecorder.stop();
    setState(() => _isRecording = false);
  }

  Future<void> _playRecording() async {
    if (_recordedFilePath != null) {
      await _audioPlayer.setSourceUrl(_recordedFilePath!);
      await _audioPlayer.play(_audioPlayer.source!);
    }
  }

  Future<void> _initializeService() async {
    final initialized = await _audioService.initialize();
    setState(() => _isInitialized = initialized);
  }

  Future<void> _toggleStreaming() async {
    if (!_isInitialized) return;

    setState(() => _isStreaming = !_isStreaming);

    if (_isStreaming) {
      await _audioService.startStreaming();
    } else {
      await _audioService.stopStreaming();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Streaming'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_isInitialized)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: _toggleStreaming,
                icon: Icon(_isStreaming ? Icons.stop : Icons.mic),
                label:
                    Text(_isStreaming ? 'Stop Streaming' : 'Start Streaming'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: _isStreaming ? Colors.red : Colors.blue,
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () =>
                  _isRecording ? _stopRecording() : _startRecording(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
              ),
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            if (_recordedFilePath != null) ...[
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _playRecording,
                child: const Text('Play Recording'),
              ),
              Text('File saved at: $_recordedFilePath'),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }
}
