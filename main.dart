import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONFIG
// ─────────────────────────────────────────────────────────────────────────────
const _apiKey =
    '38e68846932feffc7010cb213b9fe1673db38f328198ec5883ac8dceaad9abd0';
const _defaultAgentId = 'agent_4701kjk172s4e9dvzr801ctxd77w';
const _inputSampleRate = 16000;

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ElevenApp());
}

class ElevenApp extends StatelessWidget {
  const ElevenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
      ),
      home: const ConversationScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MESSAGE MODEL
// ─────────────────────────────────────────────────────────────────────────────
enum Role { user, agent }

class ChatMessage {
  final Role role;
  final String text;
  final DateTime time;
  ChatMessage({required this.role, required this.text, DateTime? time})
      : time = time ?? DateTime.now();
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with TickerProviderStateMixin {
  // ── state ──────────────────────────────────────────────────────────────
  String _agentId = _defaultAgentId;
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollCtrl = ScrollController();

  bool _isConnected = false;
  bool _isListening = false;
  bool _agentSpeaking = false;
  String _statusText = 'Tap to start';
  String _pendingUserTranscript = '';
  String _pendingAgentText = '';
  String? _conversationId;

  // ── audio output format from server ────────────────────────────────────
  String _audioOutputFormat = 'pcm_16000';
  int _outputSampleRate = 16000;

  // ── networking ─────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;

  // ── audio recording (record package) ───────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<List<int>>? _micSub;

  // ── audio playback ─────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _playerSub;
  final List<int> _audioBuffer = [];
  int _audioChunkIndex = 0;

  // ── animation ──────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _orbCtrl;
  late Animation<double> _pulseAnim;

  // ── mic level for waveform ─────────────────────────────────────────────
  double _micLevel = 0.0;
  final List<double> _waveformHistory = List.filled(40, 0.0);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _disconnect();
    _pulseCtrl.dispose();
    _orbCtrl.dispose();
    _scrollCtrl.dispose();
    _playerSub?.cancel();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────
  // CONNECTION
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _connect() async {
    if (_agentId.trim().isEmpty) {
      _showAgentIdDialog();
      return;
    }

    // Check mic permission via the record package
    if (!await _recorder.hasPermission()) {
      _setStatus('Microphone permission denied');
      return;
    }

    _setStatus('Connecting...');

    try {
      String wsUrl;

      // Try signed URL first (private agents), fallback to direct (public)
      try {
        final httpClient = HttpClient();
        final request = await httpClient.postUrl(Uri.parse(
          'https://api.elevenlabs.io/v1/convai/conversation/get-signed-url?agent_id=$_agentId',
        ));
        request.headers.set('xi-api-key', _apiKey);
        request.headers.set('Content-Type', 'application/json');
        request.contentLength = 0;
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        httpClient.close();

        if (response.statusCode == 200) {
          final json = jsonDecode(body) as Map<String, dynamic>;
          final signedUrl = json['signed_url'] as String?;
          if (signedUrl != null && signedUrl.isNotEmpty) {
            wsUrl = signedUrl;
          } else {
            wsUrl =
                'wss://api.elevenlabs.io/v1/convai/conversation?agent_id=$_agentId';
          }
        } else {
          debugPrint(
              'Signed URL failed (${response.statusCode}), using direct');
          wsUrl =
              'wss://api.elevenlabs.io/v1/convai/conversation?agent_id=$_agentId';
        }
      } catch (e) {
        debugPrint('Signed URL error: $e, using direct');
        wsUrl =
            'wss://api.elevenlabs.io/v1/convai/conversation?agent_id=$_agentId';
      }

      debugPrint('Connecting to: $wsUrl');

      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        pingInterval: const Duration(seconds: 15),
      );

      await _channel!.ready;

      _wsSub = _channel!.stream.listen(
        _onWsMessage,
        onError: (e) {
          debugPrint('WS error: $e');
          _onDisconnected('Connection error');
        },
        onDone: () => _onDisconnected('Disconnected'),
      );

      setState(() {
        _isConnected = true;
        _statusText = 'Connected - listening...';
        _messages.clear();
      });

      _startRecording();
    } catch (e) {
      debugPrint('Connect error: $e');
      _setStatus('Connection failed: ${e.toString().split('\n').first}');
    }
  }

  void _disconnect() {
    _stopRecording();
    _stopPlayback();
    _wsSub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _wsSub = null;
    _conversationId = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isListening = false;
        _agentSpeaking = false;
        _statusText = 'Tap to start';
        _pendingUserTranscript = '';
        _pendingAgentText = '';
      });
    }
  }

  void _onDisconnected(String reason) {
    _stopRecording();
    _stopPlayback();
    _wsSub?.cancel();
    _channel = null;
    _wsSub = null;
    _conversationId = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isListening = false;
        _agentSpeaking = false;
        _statusText = reason;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // RECORDING (record package — streams PCM16 from mic)
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _inputSampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );

      _micSub = stream.listen((List<int> data) {
        final bytes = Uint8List.fromList(data);

        // Send raw PCM bytes as base64 to WebSocket
        if (_channel != null && _isConnected) {
          final b64 = base64Encode(bytes);
          _channel!.sink.add(jsonEncode({'user_audio_chunk': b64}));
        }

        // Compute mic level for visualization
        _updateMicLevel(bytes);
      });

      setState(() => _isListening = true);
    } catch (e) {
      debugPrint('Recording error: $e');
      _setStatus('Mic error: ${e.toString().split('\n').first}');
    }
  }

  void _stopRecording() {
    _micSub?.cancel();
    _micSub = null;
    _recorder.stop();
    if (mounted) setState(() => _isListening = false);
  }

  void _updateMicLevel(Uint8List pcmData) {
    if (pcmData.length < 2) return;
    final byteData = ByteData.sublistView(pcmData);
    double sum = 0;
    final sampleCount = pcmData.length ~/ 2;
    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      sum += sample * sample;
    }
    final rms = sqrt(sum / sampleCount) / 32768.0;
    if (mounted) {
      setState(() {
        _micLevel = rms.clamp(0.0, 1.0);
        _waveformHistory.removeAt(0);
        _waveformHistory.add(_micLevel);
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // WEBSOCKET MESSAGE HANDLING
  // ─────────────────────────────────────────────────────────────────────
  void _onWsMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? '';

      switch (type) {
        case 'conversation_initiation_metadata':
          final meta = msg['conversation_initiation_metadata_event']
              as Map<String, dynamic>?;
          if (meta != null) {
            _conversationId = meta['conversation_id'] as String?;

            // Parse audio output format from agent config
            final agentOutput =
                meta['agent_output_audio_format'] as String?;
            if (agentOutput != null && agentOutput.isNotEmpty) {
              _audioOutputFormat = agentOutput;
              final parts = agentOutput.split('_');
              if (parts.length == 2) {
                _outputSampleRate = int.tryParse(parts[1]) ?? 16000;
              }
              debugPrint(
                  'Audio output format: $_audioOutputFormat ($_outputSampleRate Hz)');
            }

            debugPrint('Conversation started: $_conversationId');
          }
          break;

        case 'user_transcript':
          final evt =
              msg['user_transcription_event'] as Map<String, dynamic>?;
          if (evt != null) {
            final text = evt['user_transcript'] as String? ?? '';
            final isFinal = evt['is_final'] as bool? ?? false;
            setState(() => _pendingUserTranscript = text);
            if (isFinal && text.trim().isNotEmpty) {
              _commitMessage(Role.user, text.trim());
              setState(() => _pendingUserTranscript = '');
            }
          }
          break;

        case 'agent_response':
          final evt =
              msg['agent_response_event'] as Map<String, dynamic>?;
          if (evt != null) {
            final text = evt['agent_response'] as String? ?? '';
            setState(() {
              _pendingAgentText += text;
              _agentSpeaking = true;
              _statusText = 'Speaking...';
            });
          }
          break;

        case 'audio':
          final evt = msg['audio_event'] as Map<String, dynamic>?;
          if (evt != null) {
            final b64 = evt['audio_base_64'] as String? ?? '';
            if (b64.isNotEmpty) {
              final bytes = base64Decode(b64);
              _audioBuffer.addAll(bytes);
            }
          }
          // Start playback after buffering ~0.3s of audio
          final bytesPerSecond = _outputSampleRate * 2;
          if (_audioBuffer.length > (bytesPerSecond * 0.3).toInt() &&
              !_player.playing) {
            _playBufferedAudio();
          }
          break;

        case 'agent_response_end':
          if (_pendingAgentText.trim().isNotEmpty) {
            _commitMessage(Role.agent, _pendingAgentText.trim());
          }
          setState(() => _pendingAgentText = '');
          if (_audioBuffer.isNotEmpty && !_player.playing) {
            _playBufferedAudio();
          }
          break;

        case 'interruption':
          _stopPlayback();
          setState(() {
            _agentSpeaking = false;
            _statusText = 'Connected - listening...';
            _pendingAgentText = '';
          });
          break;

        case 'ping':
          final eventId = msg['ping_event']?['event_id'];
          if (eventId != null) {
            _channel?.sink.add(jsonEncode({
              'type': 'pong',
              'event_id': eventId,
            }));
          }
          break;

        default:
          debugPrint('WS event: $type');
      }
    } catch (e) {
      debugPrint('Message parse error: $e');
    }
  }

  void _commitMessage(Role role, String text) {
    setState(() {
      _messages.add(ChatMessage(role: role, text: text));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // AUDIO PLAYBACK
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _playBufferedAudio() async {
    if (_audioBuffer.isEmpty) return;

    final rawBytes = Uint8List.fromList(_audioBuffer);
    _audioBuffer.clear();
    _audioChunkIndex++;

    try {
      final dir = await getTemporaryDirectory();
      final bool isMp3 = _audioOutputFormat.startsWith('mp3');
      final String ext = isMp3 ? 'mp3' : 'wav';
      final file = File('${dir.path}/ai_audio_$_audioChunkIndex.$ext');

      if (isMp3) {
        await file.writeAsBytes(rawBytes);
      } else {
        final wavBytes = _createWav(rawBytes, _outputSampleRate);
        await file.writeAsBytes(wavBytes);
      }

      // Cancel previous player state listener to avoid leaks
      await _playerSub?.cancel();

      await _player.setFilePath(file.path);
      _player.play();

      setState(() {
        _agentSpeaking = true;
        _statusText = 'Speaking...';
      });

      _playerSub = _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() {
              _agentSpeaking = false;
              _statusText = 'Connected - listening...';
            });
          }
          // Play next chunk if more audio arrived while playing
          if (_audioBuffer.isNotEmpty) {
            _playBufferedAudio();
          }
        }
      });
    } catch (e) {
      debugPrint('Playback error: $e');
    }
  }

  void _stopPlayback() {
    _player.stop();
    _playerSub?.cancel();
    _playerSub = null;
    _audioBuffer.clear();
    if (mounted) setState(() => _agentSpeaking = false);
  }

  Uint8List _createWav(Uint8List pcmData, int sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final dataLength = pcmData.length;
    final fileLength = 36 + dataLength;
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);

    final header = ByteData(44);
    header.setUint32(0, 0x52494646, Endian.big); // RIFF
    header.setUint32(4, fileLength, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big); // WAVE
    header.setUint32(12, 0x666D7420, Endian.big); // fmt
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint32(36, 0x64617461, Endian.big); // data
    header.setUint32(40, dataLength, Endian.little);

    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...pcmData,
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────
  // UI HELPERS
  // ─────────────────────────────────────────────────────────────────────
  void _setStatus(String text) {
    if (mounted) setState(() => _statusText = text);
  }

  void _showAgentIdDialog() {
    final ctrl = TextEditingController(text: _agentId);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Agent Setup',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your ElevenLabs Conversational AI Agent ID.\n\n'
              'Create one free at:\nelevenlabs.io/app/conversational-ai',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Paste agent ID...',
                hintStyle:
                    TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _agentId = ctrl.text.trim());
              Navigator.pop(ctx);
              if (_agentId.isNotEmpty) _connect();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _toggle() {
    if (_isConnected) {
      _disconnect();
    } else {
      _connect();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0A1A),
              Color(0xFF0F0F2D),
              Color(0xFF0A0A1A)
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildBody()),
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _connectionDot(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusText,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.settings_rounded,
                color: Colors.white.withOpacity(0.4), size: 22),
            onPressed: _showAgentIdDialog,
          ),
        ],
      ),
    );
  }

  Widget _connectionDot() {
    final color = _isConnected
        ? (_agentSpeaking
            ? const Color(0xFF6C63FF)
            : const Color(0xFF00E676))
        : Colors.white.withOpacity(0.25);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: _isConnected
            ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 8)]
            : [],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: Center(child: _buildOrb()),
        ),
        const SizedBox(height: 8),
        if (_isListening) _buildWaveform(),
        const SizedBox(height: 8),
        if (_pendingUserTranscript.isNotEmpty ||
            _pendingAgentText.isNotEmpty)
          _buildPendingText(),
        Expanded(child: _buildMessageList()),
      ],
    );
  }

  Widget _buildOrb() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _orbCtrl]),
      builder: (context, _) {
        final pulseScale = _agentSpeaking ? _pulseAnim.value : 1.0;
        final rotation = _orbCtrl.value * 2 * pi;
        const baseSize = 120.0;
        final size = baseSize * pulseScale;

        final glowColor = _isConnected
            ? (_agentSpeaking
                ? const Color(0xFF6C63FF)
                : (_isListening
                    ? Color.lerp(
                        const Color(0xFF00E676),
                        const Color(0xFF6C63FF),
                        _micLevel.clamp(0.0, 1.0))!
                    : const Color(0xFF2A2A4A)))
            : const Color(0xFF1A1A2E);

        return Container(
          width: size + 40,
          height: size + 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(0.3 + (_micLevel * 0.4)),
                blurRadius: 40 + (_micLevel * 60),
                spreadRadius: 5 + (_micLevel * 15),
              ),
            ],
          ),
          child: Center(
            child: CustomPaint(
              size: Size(size, size),
              painter: _OrbPainter(
                rotation: rotation,
                intensity:
                    _isConnected ? (0.5 + _micLevel * 0.5) : 0.15,
                primaryColor: glowColor,
                speaking: _agentSpeaking,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 50),
        child: CustomPaint(
          size: const Size(double.infinity, 40),
          painter: _WaveformPainter(
            levels: _waveformHistory,
            color: _agentSpeaking
                ? const Color(0xFF6C63FF)
                : const Color(0xFF00E676),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Column(
        children: [
          if (_pendingUserTranscript.isNotEmpty)
            _PendingBubble(
                text: _pendingUserTranscript, isUser: true),
          if (_pendingAgentText.isNotEmpty)
            _PendingBubble(text: _pendingAgentText, isUser: false),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          _isConnected ? 'Start talking...' : 'Tap the mic to begin',
          style: TextStyle(
              color: Colors.white.withOpacity(0.2), fontSize: 15),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) => _MessageBubble(message: _messages[i]),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.only(bottom: 24, top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected
                    ? const Color(0xFFFF4B4B).withOpacity(0.15)
                    : const Color(0xFF6C63FF).withOpacity(0.15),
                border: Border.all(
                  color: _isConnected
                      ? const Color(0xFFFF4B4B).withOpacity(0.6)
                      : const Color(0xFF6C63FF).withOpacity(0.6),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isConnected
                            ? const Color(0xFFFF4B4B)
                            : const Color(0xFF6C63FF))
                        .withOpacity(0.2),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                _isConnected ? Icons.stop_rounded : Icons.mic_rounded,
                color: _isConnected
                    ? const Color(0xFFFF4B4B)
                    : const Color(0xFF6C63FF),
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isConnected ? 'Tap to end' : 'Tap to start',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTERS
// ─────────────────────────────────────────────────────────────────────────────
class _OrbPainter extends CustomPainter {
  final double rotation;
  final double intensity;
  final Color primaryColor;
  final bool speaking;

  _OrbPainter({
    required this.rotation,
    required this.intensity,
    required this.primaryColor,
    required this.speaking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withOpacity(intensity * 0.3),
          primaryColor.withOpacity(0),
        ],
      ).createShader(
          Rect.fromCircle(center: center, radius: radius * 1.2));
    canvas.drawCircle(center, radius * 1.2, glowPaint);

    final orbPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          0.3 * cos(rotation),
          0.3 * sin(rotation),
        ),
        radius: 0.9,
        colors: [
          Color.lerp(primaryColor, Colors.white, 0.3)!
              .withOpacity(intensity),
          primaryColor.withOpacity(intensity * 0.8),
          primaryColor.withOpacity(intensity * 0.3),
          const Color(0xFF0A0A1A).withOpacity(0.1),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(
          Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, orbPaint);

    final highlightOffset = Offset(
      center.dx + radius * 0.35 * cos(rotation * 1.5),
      center.dy + radius * 0.35 * sin(rotation * 1.5),
    );
    final highlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(intensity * 0.2),
          Colors.white.withOpacity(0),
        ],
      ).createShader(Rect.fromCircle(
          center: highlightOffset, radius: radius * 0.5));
    canvas.drawCircle(
        highlightOffset, radius * 0.5, highlightPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = primaryColor.withOpacity(intensity * 0.4);
    canvas.drawCircle(center, radius - 1, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}

class _WaveformPainter extends CustomPainter {
  final List<double> levels;
  final Color color;

  _WaveformPainter({required this.levels, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / levels.length;
    final centerY = size.height / 2;

    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      final height = max(2.0, level * size.height * 2.5);
      final x = i * barWidth + barWidth / 2;

      final paint = Paint()
        ..color = color.withOpacity(0.3 + level * 0.7)
        ..strokeWidth = max(1.5, barWidth - 2)
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _PendingBubble extends StatelessWidget {
  final String text;
  final bool isUser;

  const _PendingBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.white.withOpacity(0.06)
              : const Color(0xFF6C63FF).withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                (isUser ? Colors.white : const Color(0xFF6C63FF))
                    .withOpacity(0.1),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == Role.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.white.withOpacity(0.1)
              : const Color(0xFF6C63FF).withOpacity(0.12),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'AI',
                  style: TextStyle(
                    color:
                        const Color(0xFF6C63FF).withOpacity(0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
