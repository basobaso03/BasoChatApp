import 'dart:async'; // For Timer (throttling) and async
import 'dart:io'; // For File operations
import 'dart:typed_data'; // For Uint8List (image bytes)
import 'package:flutter/foundation.dart'; // For listEquals

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:google_generative_ai/google_generative_ai.dart'; // Gemini AI
import 'package:sqflite/sqflite.dart'; // SQLite
import 'package:path/path.dart' as p; // Path manipulation
import 'package:path_provider/path_provider.dart'; // For getting app directories
import 'package:uuid/uuid.dart'; // UUID generation
import 'package:flutter_dotenv/flutter_dotenv.dart'; // For API Key
import 'package:url_launcher/url_launcher.dart'; // For About Us link
import 'package:connectivity_plus/connectivity_plus.dart'; // For connectivity
import 'package:file_picker/file_picker.dart'; // For picking files
import 'package:permission_handler/permission_handler.dart'; // For permissions
import 'package:speech_to_text/speech_to_text.dart'; // For speech-to-text
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:mime/mime.dart'; // For determining MIME types
import 'dart:convert'; // For jsonEncode and jsonDecode
import 'package:shared_preferences/shared_preferences.dart'; // For persisting model choice


// Import the message widget (adjust path if necessary)
import '../models/academic_source.dart';
import '../services/academic_search_service.dart';
import '../widgets/academic_source_card.dart';
import '../widgets/chat_message_widget.dart';

/// Debug-only logger — compiled out in release builds.
void _log(String msg) {
  if (kDebugMode) debugPrint(msg);
}

String systemInstruction ='''You are BasoChat App, an experienced and patient teacher who excels at making complex topics understandable.

### Your Primary Role:
*   Teach students on their academic questions with simple, detailed, and clear explanations. Avoid shallow answers.
*   Assist students with life planning and general questions, offering thoughtful guidance.

### Your Process:
1.  **Analyze the Question:** Before answering, take a moment to thoroughly understand the student's core question.
2.  **Ask for Clarity:** If a question is ambiguous or lacks context, ask clarifying questions to ensure you fully understand what the student needs.
3.  **Provide Depth:** Explain concepts thoroughly, breaking them down into smaller, easy-to-digest parts. Use analogies and simple examples where possible.
4.  **Encourage Understanding:** After explaining, check in with the student to ensure they are following along and grasp the material (e.g., "Does that make sense so far?" or "Could you try explaining that back to me?").''';
// --- MODIFIED AppChatMessage Class ---
// Can hold either text or image data for display
class AppChatMessage {
  final String messageId; // --- ADDED: Unique ID for each message ---
  final String? text; // Make text nullable
  final Uint8List? imageBytes; // Add field for image data
  final bool isUser;
  final bool? _isQueued; // flag for offline queued messages
  final bool? _isEdited;
  final List<String>? attachmentIds;

  bool get isQueued => _isQueued ?? false;
  bool get isEdited => _isEdited ?? false;

  AppChatMessage({
    required this.messageId,
    this.text,
    this.imageBytes,
    required this.isUser,
    bool? isQueued = false,
    bool? isEdited = false,
    this.attachmentIds,
  }) : _isQueued = isQueued,
       _isEdited = isEdited,
       assert(text != null || imageBytes != null || (attachmentIds != null && attachmentIds.isNotEmpty),
            'AppChatMessage must have either text, imageBytes, or attachmentIds');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppChatMessage &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId && // Compare ID
          text == other.text &&
          // Use listEquals for proper byte comparison
          listEquals(imageBytes, other.imageBytes) &&
          isUser == other.isUser &&
          isQueued == other.isQueued &&
          isEdited == other.isEdited &&
          listEquals(attachmentIds, other.attachmentIds); // Compare attachmentIds

  @override
  int get hashCode =>
      messageId.hashCode ^
      text.hashCode ^
      imageBytes.hashCode ^
      isUser.hashCode ^
      isQueued.hashCode ^
      isEdited.hashCode ^
      attachmentIds.hashCode;

  AppChatMessage copyWith({bool? isQueued, bool? isEdited}) {
    return AppChatMessage(
      messageId: messageId,
      text: text,
      imageBytes: imageBytes,
      isUser: isUser,
      isQueued: isQueued ?? this.isQueued,
      isEdited: isEdited ?? this.isEdited,
      attachmentIds: attachmentIds,
    );
  }
}


// Data structure for attachments (used in state and DB interaction)
class AppAttachment {
  final String id; // Unique ID for this attachment record (used as PK in DB)
  final String originalName;
  final String storedPath; // Full path where the file is stored locally
  final String? mimeType; // Detected MIME type (e.g., 'application/pdf')

  AppAttachment({
    required this.id,
    required this.originalName,
    required this.storedPath,
    this.mimeType,
  });

  // Convert to Map for database storage
  Map<String, dynamic> toMap(String sessionId, int timestamp) {
    return {
      'id': id,
      'session_id': sessionId,
      'original_name': originalName,
      'stored_path': storedPath,
      'mime_type': mimeType,
      'timestamp': timestamp,
    };
  }

  // Create from Map (retrieved from database)
  factory AppAttachment.fromMap(Map<String, dynamic> map) {
    return AppAttachment(
      id: map['id'] as String,
      originalName: map['original_name'] as String,
      storedPath: map['stored_path'] as String,
      mimeType: map['mime_type'] as String?,
    );
  }
}

enum StudyMode {
  explain,
  examPrep,
  researchAssistant,
  academicWriting,
  literatureReview,
  lifeGuidance,
}

extension StudyModeLabel on StudyMode {
  String get label {
    switch (this) {
      case StudyMode.explain:
        return 'Explain Simply';
      case StudyMode.examPrep:
        return 'Exam Prep';
      case StudyMode.researchAssistant:
        return 'Research Assistant';
      case StudyMode.academicWriting:
        return 'Academic Writing';
      case StudyMode.literatureReview:
        return 'Literature Review';
      case StudyMode.lifeGuidance:
        return 'Life Guidance';
    }
  }

  String get shortLabel {
    switch (this) {
      case StudyMode.explain:
        return 'Explain';
      case StudyMode.examPrep:
        return 'Exam';
      case StudyMode.researchAssistant:
        return 'Research';
      case StudyMode.academicWriting:
        return 'Writing';
      case StudyMode.literatureReview:
        return 'Review';
      case StudyMode.lifeGuidance:
        return 'Guidance';
    }
  }
}


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // --- State Variables ---
  GenerativeModel? _model;
  Database? _database;
  final AcademicSearchService _academicSearchService = const AcademicSearchService();
  final Uuid _uuid = const Uuid();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _chatScrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isLoading = false; // General loading state (API calls, file processing)
  bool _isStreamingResponse = false;

  final List<AppChatMessage> _currentChatMessages = [];
  List<Content> _chatHistoryForAI = [];
  String? _currentSessionId;
  List<Map<String, dynamic>> _chatSessionsForSidebar = [];

  Timer? _updateThrottleTimer;

  /// Maximum number of user+model turns kept in the in-memory AI history.
  /// Prevents unbounded RAM growth in long conversations.
  static const int _maxHistoryLength = 40;

  String? _selectedMessageTextForCopy;
  int? _selectedMessageIndex;

  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  List<AppAttachment> _currentAttachments = [];
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastRecognizedWords = "";
  bool _showRecordingIndicator = false;
  bool _isSpeechInitializing = true; // Start as true
  String? _editingMessageId;
  bool _isResearching = false;
  bool _useWebReferences = true;
  bool _groundedAcademicMode = true;
  bool _smartRoutingEnabled = true;
  String _citationStyle = 'APA';
  StudyMode _studyMode = StudyMode.researchAssistant;
  List<AcademicSource> _recentAcademicSources = [];
  final Map<String, List<AcademicSource>> _messageSources = {};
  final Set<String> _webToolMessageIds = <String>{};
  final Map<String, String> _webToolStatusByMessageId = <String, String>{};
  final Set<String> _savedSourceIds = <String>{};
  String? _lastResearchQuery;
  String? _activeResearchQuery;
  String _researchProviderFilter = 'All';
  String _researchSearchQuery = '';
  bool _researchShowSavedOnly = false;
  StreamSubscription<GenerateContentResponse>? _responseStreamSubscription;
  Completer<void>? _responseStreamDoneCompleter;
  bool _cancelStreamingResponseRequested = false;

  bool get _isBusyBlockingUi => _isLoading && !_isStreamingResponse;

  String _selectedModelId = 'gemini-3-flash-preview';
  static const List<Map<String, String>> _availableModels = [
    {'id': 'gemini-3-flash-preview', 'name': 'Gemini 3', 'tag': 'Best overall'},
    {'id': 'gemini-3.1-flash-lite-preview', 'name': 'Gemini 3 Lite', 'tag': 'Fast and light'},
    {'id': 'gemini-2.5-flash', 'name': 'Gemini 2.5 Flash', 'tag': 'Balanced'},
    {'id': 'gemini-2.5-flash-lite', 'name': 'Gemini 2.5 Lite', 'tag': 'Fastest'},
  ];

  @override
  void initState() {
    super.initState();
    _log("initState: Starting ChatScreen initialization...");
    WidgetsBinding.instance.addObserver(this);
    _loadSavedPreferences();
    _initializePermissionsAndSpeech(); // Consolidated permission and speech init
    _initializeDatabaseAndLoadChat();
    _initializeConnectivityListener();
    _log("initState: Initialization sequence started.");
  }

  Future<void> _initializeDatabaseAndLoadChat() async {
    _log("Initializing database...");
    await _initializeDatabase();
    if (mounted) {
      _log("Database initialized. Loading last session or setting up new chat...");
      await _loadLastSessionOrSetupNew();
      _log("Chat loaded/setup complete.");
    } else {
      _log("Widget unmounted during database initialization.");
    }
  }

  void _initializeModel() {
    _log("Initializing Generative Model with $_selectedModelId...");
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      _log('CRITICAL ERROR: GEMINI_API_KEY not found or empty in .env file.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) _addErrorMessageToChat("Configuration Error: Could not initialize AI. API Key is missing.");
      });
      return;
    }
    try {
      _model = GenerativeModel(
        model: _selectedModelId,
        apiKey: apiKey,
        systemInstruction: Content('system', [TextPart(systemInstruction)]),
      );
      _log("Generative Model initialized successfully.");
    } catch (e) {
      _log("CRITICAL: Error initializing Generative Model: $e");
      WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) _addErrorMessageToChat("Initialization Error: Failed to set up AI model.");
      });
    }
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_model_id');
      if (saved != null && _availableModels.any((m) => m['id'] == saved)) {
        _selectedModelId = saved;
      } else if (saved != null) {
        await prefs.setString('selected_model_id', _selectedModelId);
      }
      _citationStyle = prefs.getString('citation_style') ?? 'APA';
      _useWebReferences = prefs.getBool('use_web_references') ?? true;
      _groundedAcademicMode = prefs.getBool('grounded_academic_mode') ?? true;
      _smartRoutingEnabled = prefs.getBool('smart_routing_enabled') ?? true;
      final studyModeIndex = prefs.getInt('study_mode_index') ?? StudyMode.researchAssistant.index;
      _studyMode = StudyMode.values[studyModeIndex.clamp(0, StudyMode.values.length - 1)];
    } catch (e) {
      _log('Could not load saved preferences: $e');
    }
    _initializeModel();
  }

  Future<void> _changeModel(String modelId) async {
    if (modelId == _selectedModelId) return;
    setState(() => _selectedModelId = modelId);
    try {
      await _saveStringPreference('selected_model_id', modelId);
    } catch (e) {
      _log('Could not save model preference: $e');
    }
    _initializeModel();
    _chatHistoryForAI.clear();
    _showSnackbar('Switched to ${_availableModels.firstWhere((m) => m['id'] == modelId)['name']}');
  }

  Future<void> _saveStringPreference(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveBoolPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveIntPreference(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _changeCitationStyle(String value) async {
    if (value == _citationStyle) return;
    setState(() => _citationStyle = value);
    await _saveStringPreference('citation_style', value);
    _showSnackbar('Citation style set to $value');
  }

  Future<void> _changeStudyMode(StudyMode mode) async {
    if (mode == _studyMode) return;
    setState(() => _studyMode = mode);
    await _saveIntPreference('study_mode_index', mode.index);
    _showSnackbar('Study mode: ${mode.label}');
  }

  Future<void> _setUseWebReferences(bool value) async {
    setState(() => _useWebReferences = value);
    await _saveBoolPreference('use_web_references', value);
  }

  Future<void> _setGroundedAcademicMode(bool value) async {
    setState(() => _groundedAcademicMode = value);
    await _saveBoolPreference('grounded_academic_mode', value);
  }

  Future<void> _setSmartRoutingEnabled(bool value) async {
    setState(() => _smartRoutingEnabled = value);
    await _saveBoolPreference('smart_routing_enabled', value);
  }

  void _showAssistantSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1826),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Assistant Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    const Text('Study mode', style: TextStyle(color: Color(0xFF64D2FF), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: StudyMode.values.map((mode) {
                        final selected = mode == _studyMode;
                        return ChoiceChip(
                          label: Text(mode.label),
                          selected: selected,
                          onSelected: (_) async {
                            await _changeStudyMode(mode);
                            setModalState(() {});
                          },
                          selectedColor: const Color(0xFF0F5244),
                          labelStyle: TextStyle(color: selected ? const Color(0xFF00C9A7) : Colors.white),
                          backgroundColor: const Color(0xFF111E2E),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111E2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF1E3A54)),
                      ),
                      child: Text(
                        switch (_studyMode) {
                          StudyMode.explain => 'Detailed teaching mode. The assistant breaks ideas into smaller steps, uses examples, and explains why each step matters so the user can truly understand the topic.',
                          StudyMode.examPrep => 'Revision mode. The assistant still explains clearly, but it focuses more on recall, likely questions, memory aids, and exam technique.',
                          StudyMode.researchAssistant => 'Evidence analysis mode. The assistant compares studies, methods, strengths, weaknesses, and uncertainty instead of giving only a short answer.',
                          StudyMode.academicWriting => 'Writing support mode. The assistant improves structure, argument quality, and grounding while avoiding fabricated scholarship or misconduct support.',
                          StudyMode.literatureReview => 'Synthesis mode. The assistant groups sources into themes, methods, findings, contradictions, and gaps for a literature review style response.',
                          StudyMode.lifeGuidance => 'Real-life guidance mode. Users can describe personal situations, dilemmas, plans, or uncertainty, and the assistant will analyze the situation, clarify options, weigh tradeoffs, and suggest grounded next steps.',
                        },
                        style: const TextStyle(color: Color(0xFFCDE0EC), height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Citation style', style: TextStyle(color: Color(0xFF64D2FF), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _citationStyle,
                      dropdownColor: const Color(0xFF111E2E),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF111E2E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      items: const ['APA', 'MLA', 'Chicago', 'Harvard', 'IEEE']
                          .map((style) => DropdownMenuItem(value: style, child: Text(style)))
                          .toList(),
                      onChanged: (value) async {
                        if (value == null) return;
                        await _changeCitationStyle(value);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: _useWebReferences,
                      onChanged: (value) async {
                        await _setUseWebReferences(value);
                        setModalState(() {});
                      },
                      title: const Text('Use web references', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Search scholarly providers for newer evidence.', style: TextStyle(color: Color(0xFF8BA3B0))),
                    ),
                    SwitchListTile.adaptive(
                      value: _groundedAcademicMode,
                      onChanged: (value) async {
                        await _setGroundedAcademicMode(value);
                        setModalState(() {});
                      },
                      title: const Text('Grounded citation mode', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Refuse invented references and cite only retrieved evidence.', style: TextStyle(color: Color(0xFF8BA3B0))),
                    ),
                    SwitchListTile.adaptive(
                      value: _smartRoutingEnabled,
                      onChanged: (value) async {
                        await _setSmartRoutingEnabled(value);
                        setModalState(() {});
                      },
                      title: const Text('Smart task routing', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Use stronger or lighter Gemini variants depending on the task.', style: TextStyle(color: Color(0xFF8BA3B0))),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showModelSelector() {
    const Color kAccent = Color(0xFF00C9A7);
    const Color kSurface = Color(0xFF0D1826);
    const Color kBorder = Color(0xFF1E3A54);

    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Select AI Model', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._availableModels.map((model) {
              final isSelected = model['id'] == _selectedModelId;
              return ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  _changeModel(model['id']!);
                },
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(colors: [Color(0xFF00C9A7), Color(0xFF0097A7)])
                        : null,
                    color: isSelected ? null : const Color(0xFF111E2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSelected ? kAccent : kBorder),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, size: 20, color: isSelected ? Colors.white : const Color(0xFF64D2FF)),
                ),
                title: Text(model['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                subtitle: Text(model['tag']!, style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 12)),
                trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: kAccent) : null,
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _initializeConnectivityListener() {
    _log("Initializing connectivity listener...");
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _updateConnectionStatus(results);
    });
    Connectivity().checkConnectivity().then(_updateConnectionStatus);
    _log("Connectivity listener initialized.");
  }

  Future<void> _initializePermissionsAndSpeech() async {
    _log("Initializing permissions and then speech capability...");
    // First, request permissions and wait for the user's response
    bool permissionsGranted = await _requestPermissions();

    if (permissionsGranted) {
      // If permissions were granted, proceed to initialize speech
      await _initSpeech();
    } else {
      // If permissions were not granted, update state accordingly
      _log("Microphone permission not granted. Speech input will be disabled.");
      if (mounted) {
        setState(() {
          _speechEnabled = false;
          _isSpeechInitializing = false; // Crucial: ensure initializing is false
        });
      }
    }
    _log("Permissions and speech initialization sequence complete.");
  }

  Future<bool> _requestPermissions() async {
    _log("Requesting permissions...");
    var micStatus = await Permission.microphone.request();
    _log("Microphone permission status: $micStatus");
    if (micStatus.isDenied) {
      _showSnackbar("Microphone permission is needed for voice input.", duration: const Duration(seconds: 4), bgColor: Colors.orange[800]);
    } else if (micStatus.isPermanentlyDenied) {
       _showSnackbar("Microphone permission permanently denied. Please enable it in app settings.", duration: const Duration(seconds: 5), bgColor: Colors.redAccent);
    }
    _log("Permission requests complete.");
    return micStatus.isGranted;
  }

  Future<void> _initSpeech() async {
    _log("Initializing SpeechToText...");
    if (!mounted) {
      _log("Speech init aborted: Widget not mounted.");
      return;
    }
    // Ensure _isSpeechInitializing is true before starting
    if (!_isSpeechInitializing) {
      setState(() { _isSpeechInitializing = true; });
    }

    bool enabled = false;
    try {
      enabled = await _speechToText.initialize(
        onError: _speechErrorListener,
        onStatus: _speechStatusListener,
        debugLogging: false, // Set to true for more detailed logs from the plugin
      );
      _log("SpeechToText initialize() completed. Result: $enabled");
    } catch (e) {
      _log("Error initializing SpeechToText: $e");
      if (mounted) {
        _showSnackbar("Could not initialize voice input.", bgColor: Colors.redAccent);
      }
    } finally {
      if (mounted) {
        setState(() {
          _speechEnabled = enabled;
          _isSpeechInitializing = false;
        });
        _log("Speech initialization complete. State updated (enabled: $_speechEnabled, initializing: $_isSpeechInitializing).");
      }
    }
  }

  @override
  void dispose() {
    _log("Disposing ChatScreen State...");
    WidgetsBinding.instance.removeObserver(this);
    _chatScrollController.dispose();
    _textController.dispose();
    _inputFocusNode.dispose();
    _updateThrottleTimer?.cancel();
    _connectivitySubscription?.cancel();
    _responseStreamSubscription?.cancel();
    _speechToText.cancel(); // Ensure STT is cancelled
    _log("ChatScreen State disposed.");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _log("App Lifecycle State Changed: $state");
    if (state == AppLifecycleState.resumed) {
      Connectivity().checkConnectivity().then(_updateConnectionStatus);
      // Optionally, re-check microphone permission or re-initialize speech if needed
      // For example, if permissions were changed while app was in background
      // _initializePermissionsAndSpeech(); // Be cautious with re-initializing everything
    } else if (state == AppLifecycleState.paused) {
       if (_isListening) {
          _log("App paused, cancelling speech recognition.");
          _stopListening(cancel: true);
       }
    }
  }

  Future<void> _initializeDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'chat_history.db');
      _log("Database path: $path");

      _database = await openDatabase(
        path,
        version: 6,
        onCreate: (db, version) async {
          _log("onCreate: Creating database tables (Version $version)...");
          await _createTablesV1(db);
          await _createTablesV2(db);
          await _createTablesV4(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
           _log("onUpgrade: Upgrading database from version $oldVersion to $newVersion...");
           if (oldVersion < 2) {
              // If upgrading from a version before V2, V1 tables might not exist if it was a fresh V2 install.
              // So, ensure V1 and V2 tables are created.
              await _createTablesV1(db);
              await _createTablesV2(db);
           }
           if (oldVersion < 3) {
              await db.execute('ALTER TABLE messages ADD COLUMN is_queued INTEGER NOT NULL DEFAULT 0');
              await db.execute('ALTER TABLE messages ADD COLUMN attachment_ids_json TEXT');
              _log("DB Upgraded to V3: Added is_queued and attachment_ids_json to messages table.");
           }
            if (oldVersion < 4) {
              await _createTablesV4(db);
              _log("DB Upgraded to V4: Added academic_sources table.");
            }
              if (oldVersion < 5) {
                await db.execute('ALTER TABLE messages ADD COLUMN is_edited INTEGER NOT NULL DEFAULT 0');
                _log("DB Upgraded to V5: Added is_edited to messages table.");
              }
             if (oldVersion < 6) {
               await db.execute('ALTER TABLE messages ADD COLUMN web_tool_status TEXT');
               _log("DB Upgraded to V6: Added web_tool_status to messages table.");
             }
        },
        onOpen: (db) async {
          _log("onOpen: Database opened. Ensuring tables exist...");
          await db.execute('PRAGMA foreign_keys = ON');
          _log("Foreign key support enabled.");
          // Ensure tables are created if they somehow weren't (e.g., complex upgrade scenarios)
          // These calls are idempotent due to "IF NOT EXISTS"
          await _createTablesV1(db);
          await _createTablesV2(db);
          await _createTablesV4(db);
          _log("onOpen: Table existence check complete.");
        },
      );
    } catch (e) {
      _log("CRITICAL: Error initializing database: $e");
      if (mounted) {
        _addErrorMessageToChat("Database Error: Could not initialize storage.");
      }
    }
  }

   Future<void> _createTablesV1(Database db) async {
     _log("Creating sessions table (if not exists)...");
     await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        topic TEXT,
        last_updated INTEGER NOT NULL
      )
    ''');
     _log("Creating messages table (if not exists)...");
     await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        is_user INTEGER NOT NULL,
        text TEXT,
        timestamp INTEGER NOT NULL,
        is_queued INTEGER NOT NULL DEFAULT 0,
        is_edited INTEGER NOT NULL DEFAULT 0,
        web_tool_status TEXT,
        attachment_ids_json TEXT,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createTablesV2(Database db) async {
     _log("Creating session_attachments table (if not exists)...");
     await db.execute('''
        CREATE TABLE IF NOT EXISTS session_attachments (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          original_name TEXT NOT NULL,
          stored_path TEXT NOT NULL,
          mime_type TEXT,
          timestamp INTEGER NOT NULL,
          FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
        )
      ''');
     _log("session_attachments table created (if not exists).");
  }

    Future<void> _createTablesV4(Database db) async {
      _log("Creating academic_sources table (if not exists)...");
      await db.execute('''
        CREATE TABLE IF NOT EXISTS academic_sources (
         id TEXT PRIMARY KEY,
         session_id TEXT NOT NULL,
         message_id TEXT,
         provider TEXT NOT NULL,
         title TEXT NOT NULL,
         authors_json TEXT,
         abstract_text TEXT,
         year INTEGER,
         doi TEXT,
         url TEXT NOT NULL,
         journal TEXT,
         citation_count INTEGER,
         relevance_score REAL NOT NULL DEFAULT 0,
         query_text TEXT,
         created_at INTEGER NOT NULL,
         is_saved INTEGER NOT NULL DEFAULT 0,
         FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE,
         FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
        )
      ''');
      _log("academic_sources table created (if not exists).");
    }

  Future<String?> _getLastSessionId() async {
    if (_database == null || !_database!.isOpen) return null;
    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'sessions', columns: ['id'], orderBy: 'last_updated DESC', limit: 1,
      );
      return maps.isNotEmpty ? maps.first['id'] as String? : null;
    } catch (e) {
      _log("Error getting last session ID: $e");
      return null;
    }
  }

  Future<void> _loadMessagesForSession(String sessionId) async {
    if (_database == null || !_database!.isOpen) {
      if (mounted) _addErrorMessageToChat("Error: Cannot load chat, database unavailable.");
      return;
    }
    if (mounted) setState(() => _isLoading = true);

    try {
      _log("Loading messages and attachments for session: $sessionId");
      await _database!.transaction((txn) async {
         final messagesData = await txn.query(
           'messages', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'timestamp ASC',
         );
         final academicSourcesData = await txn.query(
           'academic_sources', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'created_at DESC',
         );

         final loadedMessages = <AppChatMessage>[];
         final loadedHistory = <Content>[];
         final loadedSourceMap = <String, List<AcademicSource>>{};
         final loadedWebToolStatuses = <String, String>{};
         final loadedRecentSources = <AcademicSource>[];
         final loadedSavedSourceIds = <String>{};
         // final loadedAttachments = <AppAttachment>[]; // Not directly used to populate _currentAttachments

         for (final sourceData in academicSourcesData) {
           final source = AcademicSource.fromDatabaseMap(sourceData);
           loadedRecentSources.add(source);
           if (source.isSaved) {
             loadedSavedSourceIds.add(source.id);
           }
           if (source.messageId != null) {
             loadedSourceMap.putIfAbsent(source.messageId!, () => <AcademicSource>[]).add(source);
           }
         }

         for (var msgData in messagesData) {
           final text = msgData['text'] as String?;
           final dbMessageId = msgData['id'] as String?;
           final isUserInt = msgData['is_user'] as int?;
           final isQueued = (msgData['is_queued'] as int? ?? 0) == 1;
           final isEdited = (msgData['is_edited'] as int? ?? 0) == 1;
           final webToolStatus = msgData['web_tool_status'] as String?;
           final attachmentIdsJson = msgData['attachment_ids_json'] as String?;
           List<String>? attachmentIds;

           if (attachmentIdsJson != null) {
             attachmentIds = List<String>.from(jsonDecode(attachmentIdsJson));
           }

           if (dbMessageId == null || isUserInt == null) {
             _log("Warning: Skipping message from DB due to missing id or is_user. Data: $msgData");
             continue;
           }
            bool hasContent = text != null || (attachmentIds != null && attachmentIds.isNotEmpty);
            if (!hasContent) {
             _log("Warning: Skipping message from DB due to missing text and no attachments. Data: $msgData");
             continue;
           }

           final isUser = isUserInt == 1;
           loadedMessages.add(AppChatMessage(
             messageId: dbMessageId,
             text: text,
             isUser: isUser,
             isQueued: isQueued,
             isEdited: isEdited,
             attachmentIds: attachmentIds,
           ));
           if (!isUser && webToolStatus != null && webToolStatus.isNotEmpty) {
             loadedWebToolStatuses[dbMessageId] = webToolStatus;
           }

           if (!isUser || (isUser && !isQueued)) {
             List<Part> partsForHistory = [];
             if (text != null) {
               partsForHistory.add(TextPart(text));
             }
             // For history, we might need to reconstruct DataParts if attachments were part of the original message to AI
             // This simplified version only adds text to history.
             // If attachments were sent to AI, their content should ideally be part of the 'Content' object.
             // For now, we'll rely on the text (which might include system notes about attachments).
             if (partsForHistory.isNotEmpty) {
                loadedHistory.add(Content(isUser ? "user" : "model", partsForHistory));
             } else if (isUser && attachmentIds != null && attachmentIds.isNotEmpty) {
                // User message with attachments but no text (and not queued)
                loadedHistory.add(Content("user", [TextPart("[User sent attachments (ID: ${dbMessageId.substring(0,5)}...)]")]));
             }
           }
         }
         _log("Loaded ${loadedMessages.length} messages for session $sessionId.");

         // We don't load all session attachments into _currentAttachments (composer)
         // _currentAttachments is for new messages.

         if (mounted) {
           setState(() {
             _currentChatMessages.clear();
             _chatHistoryForAI.clear();
             _currentAttachments.clear();

             _currentChatMessages.addAll(loadedMessages);
             _chatHistoryForAI.addAll(loadedHistory);
             _messageSources
               ..clear()
               ..addAll(loadedSourceMap);
             _webToolMessageIds
               ..clear()
               ..addAll(loadedSourceMap.keys);
             _webToolStatusByMessageId
               ..clear()
               ..addAll(loadedWebToolStatuses);
             _webToolMessageIds.addAll(
               loadedWebToolStatuses.entries
                   .where((entry) => entry.value.startsWith('used'))
                   .map((entry) => entry.key),
             );
             _recentAcademicSources = loadedRecentSources;
             _savedSourceIds
               ..clear()
               ..addAll(loadedSavedSourceIds);

             _currentSessionId = sessionId;
             _isLoading = false;
             _selectedMessageIndex = null;
             _selectedMessageTextForCopy = null;
             _isListening = false;
             _showRecordingIndicator = false;
           });
           _scrollToBottom(delayMillis: 150);
           _log("Messages & attachments loaded successfully for session $sessionId.");
         }
      });
    } catch (e) {
      _log("Error loading messages/attachments for session $sessionId: $e");
      if (mounted) {
        _addErrorMessageToChat("Error loading chat history.");
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveMessageToDatabase(AppChatMessage message, String sessionId, int timestamp, {String? webToolStatus}) async {
    if (message.text == null && message.imageBytes == null && (message.attachmentIds == null || message.attachmentIds!.isEmpty)) {
      _log("Skipping DB save: Message has no text, image, or attachments.");
      return;
    }
    if (_database == null || !_database!.isOpen) {
       _log("Error saving message: Database is not open.");
       return;
    }
    String? attachmentIdsJson;
    if (message.attachmentIds != null && message.attachmentIds!.isNotEmpty) {
      attachmentIdsJson = jsonEncode(message.attachmentIds);
    }

    try {
      await _database!.insert(
        'messages',
        {
          'id': message.messageId,
          'session_id': sessionId,
          'is_user': message.isUser ? 1 : 0,
          'text': message.text,
          'timestamp': timestamp,
          'is_queued': message.isQueued ? 1 : 0,
          'is_edited': message.isEdited ? 1 : 0,
          'web_tool_status': webToolStatus,
          'attachment_ids_json': attachmentIdsJson,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _database!.update(
        'sessions', {'last_updated': timestamp}, where: 'id = ?', whereArgs: [sessionId],
      );
      _log("Message saved to DB (Session: $sessionId, ID: ${message.messageId}, User: ${message.isUser}, Queued: ${message.isQueued})");
    } catch (e) {
      _log("Error saving message to database: $e");
    }
  }

  Future<void> _saveAttachmentsToDatabase(List<AppAttachment> attachments, String sessionId) async {
     if (_database == null || !_database!.isOpen || attachments.isEmpty) return;
     _log("Saving ${attachments.length} attachments to DB for session $sessionId...");
     final batch = _database!.batch();
     final timestamp = DateTime.now().millisecondsSinceEpoch;
     for (final attachment in attachments) {
        batch.insert('session_attachments', attachment.toMap(sessionId, timestamp), conflictAlgorithm: ConflictAlgorithm.replace);
     }
     try {
        await batch.commit(noResult: true);
        _log("Attachments saved successfully to DB.");
     } catch (e) {
        _log("Error saving attachments to database: $e");
        if (mounted) _addErrorMessageToChat("Error saving attachments.");
     }
  }

  Future<void> _saveAcademicSourcesToDatabase(List<AcademicSource> sources, String sessionId, {String? messageId, String? queryText}) async {
    if (_database == null || !_database!.isOpen || sources.isEmpty) return;
    final batch = _database!.batch();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    for (final source in sources) {
      final sourceToSave = source.copyWith(
        messageId: messageId,
        queryText: queryText,
        isSaved: _savedSourceIds.contains(source.id),
      );
      batch.insert(
        'academic_sources',
        sourceToSave.toDatabaseMap(sessionId, timestamp),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _toggleSavedSource(AcademicSource source) async {
    final shouldSave = !_savedSourceIds.contains(source.id);
    if (mounted) {
      setState(() {
        if (shouldSave) {
          _savedSourceIds.add(source.id);
        } else {
          _savedSourceIds.remove(source.id);
        }
        for (final entry in _messageSources.entries) {
          final index = entry.value.indexWhere((item) => item.id == source.id);
          if (index != -1) {
            entry.value[index] = entry.value[index].copyWith(isSaved: shouldSave);
          }
        }
        final recentIndex = _recentAcademicSources.indexWhere((item) => item.id == source.id);
        if (recentIndex != -1) {
          _recentAcademicSources[recentIndex] = _recentAcademicSources[recentIndex].copyWith(isSaved: shouldSave);
        }
      });
    }

    if (_database != null && _database!.isOpen) {
      await _database!.update(
        'academic_sources',
        {'is_saved': shouldSave ? 1 : 0},
        where: 'id = ?',
        whereArgs: [source.id],
      );
    }
    _showSnackbar(shouldSave ? 'Saved to references' : 'Removed from saved references');
  }

  Future<void> _clearChatHistory() async {
    if (_chatSessionsForSidebar.isEmpty && _currentSessionId == null) {
       _setupInitialChatState();
       return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear All History?'),
        content: const Text('This will permanently delete all chat sessions and their messages/attachments. This action cannot be undone.'),
        actions: <Widget>[
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop(false)),
          TextButton(style: TextButton.styleFrom(foregroundColor: Colors.redAccent), child: const Text('Clear All'), onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );

    if (confirm == true) {
      if (_database == null || !_database!.isOpen) {
          _log("Error clearing history: Database not open.");
          _addErrorMessageToChat("Database error. Cannot clear history.");
          return;
      }
      _log("Clearing all chat history...");
      try {
        final List<Map<String, dynamic>> allAttachments = await _database!.query('session_attachments', columns: ['stored_path']);
        for (var attData in allAttachments) {
           final path = attData['stored_path'] as String?;
           if (path != null) {
              try {
                 final file = File(path);
                 if (await file.exists()) { await file.delete(); _log("Deleted attachment file: $path"); }
              } catch (e) { _log("Error deleting attachment file $path: $e"); }
           }
        }
        int count = await _database!.delete('sessions'); // Cascading delete should handle messages and session_attachments
        _log("$count sessions (and related data) deleted from database.");
        if (mounted) {
          _setupInitialChatState();
          await _loadChatSessionsForSidebar();
          _showSnackbar("All chat sessions deleted.", duration: const Duration(seconds: 2));
        }
      } catch (e) {
        _log("Error deleting all chat sessions: $e");
        if (mounted) _addErrorMessageToChat("Error deleting chats: $e");
      }
    }
  }

  Future<void> _deleteSingleSession(String sessionId, String topic) async {
     final confirmDelete = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Delete Chat?'),
          content: Text('Are you sure you want to delete the chat "$topic"? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            TextButton(style: TextButton.styleFrom(foregroundColor: Colors.redAccent), onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        ),
      );

      if (confirmDelete == true && _database != null && _database!.isOpen) {
         _log("Deleting session $sessionId ('$topic')");
         try {
            final List<Map<String, dynamic>> sessionAttachments = await _database!.query('session_attachments', columns: ['stored_path'], where: 'session_id = ?', whereArgs: [sessionId]);
            for (var attData in sessionAttachments) {
               final path = attData['stored_path'] as String?;
               if (path != null) {
                  try {
                     final file = File(path);
                     if (await file.exists()) { await file.delete(); _log("Deleted attachment file for session $sessionId: $path"); }
                  } catch (e) { _log("Error deleting attachment file $path for session $sessionId: $e"); }
               }
            }
            int count = await _database!.delete('sessions', where: 'id = ?', whereArgs: [sessionId]); // Cascading delete
            _log("Deleted $count session(s) with ID $sessionId from DB.");
            await _loadChatSessionsForSidebar();
            if (sessionId == _currentSessionId) { _createNewChat(); }
            _showSnackbar("Chat '$topic' deleted.", duration: const Duration(seconds: 2));
         } catch (e) {
            _log("Error deleting session $sessionId: $e");
            _addErrorMessageToChat("Error deleting chat '$topic'.");
         }
      }
  }

  Future<void> _loadChatSessionsForSidebar() async {
    if (_database == null || !_database!.isOpen) return;
    try {
      final List<Map<String, dynamic>> sessions = await _database!.query(
        'sessions', columns: ['id', 'topic', 'last_updated'], orderBy: 'last_updated DESC',
      );
      if (mounted) {
        setState(() { _chatSessionsForSidebar = sessions.where((s) => s['id'] != null).toList(); });
        _log("Loaded ${_chatSessionsForSidebar.length} valid sessions for sidebar.");
      }
    } catch (e) { _log("Error loading chat sessions for sidebar: $e"); }
  }

  void _setupInitialChatState() {
    _log("Setting up initial chat state...");
    if (!mounted) return;

    setState(() {
       _currentSessionId = null;
       _currentChatMessages.clear();
       _chatHistoryForAI.clear();
       _currentAttachments.clear();
       _messageSources.clear();
       _recentAcademicSources.clear();
       _webToolMessageIds.clear();
       _webToolStatusByMessageId.clear();
       _savedSourceIds.clear();

       const initialMessageText = "Hello! I am BasoChat App!, How can I help you today?";
       final initialBotMessage = AppChatMessage(
         messageId: _uuid.v4(),
         text: initialMessageText,
         isUser: false);
       _currentChatMessages.add(initialBotMessage);

       if (_model != null) {
         _chatHistoryForAI.add(Content("model", [TextPart(initialMessageText)]));
         _log("Initial AI history set with greeting.");
       } else {
          _log("Initial chat state setup without active AI model.");
       }

       _isLoading = false;
       _selectedMessageTextForCopy = null;
       _selectedMessageIndex = null;
       _isListening = false;
       _isStreamingResponse = false;
       _cancelStreamingResponseRequested = false;
       _showRecordingIndicator = false;
       _textController.clear();
    });
    _log("Initial chat state setup complete.");
    _scrollToBottom();
  }

  Future<void> _loadLastSessionOrSetupNew() async {
     final lastSessionId = await _getLastSessionId();
     if (lastSessionId != null) {
       _log("Loading last session: $lastSessionId");
       await _loadMessagesForSession(lastSessionId);
       if (_currentChatMessages.isEmpty && mounted) {
           _log("Warning: Session $lastSessionId loaded empty or failed to load. Starting new chat.");
           _setupInitialChatState();
       }
     } else {
       _log("No previous sessions found. Setting up initial chat.");
       if (mounted) _setupInitialChatState();
     }
     if (mounted) {
       setState(() {
         _selectedMessageIndex = null;
         _selectedMessageTextForCopy = null;
         _isListening = false;
         _showRecordingIndicator = false;
       });
     }
     await _loadChatSessionsForSidebar();
  }

  Future<void> _loadChatSession(String sessionId) async {
    _log("Loading clicked session: $sessionId");
    if (sessionId == _currentSessionId || _isLoading) {
       if (MediaQuery.of(context).size.width < 700 && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) { Navigator.of(context).pop(); }
       _log("Session already loaded or currently loading. Aborting load.");
      return;
    }
     if (mounted) setState(() => _isLoading = true);
    if (MediaQuery.of(context).size.width < 700 && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
       Navigator.of(context).pop();
       await Future.delayed(const Duration(milliseconds: 250));
    }
    await _loadMessagesForSession(sessionId);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _selectedMessageTextForCopy = null;
        _selectedMessageIndex = null;
        _isListening = false;
        _showRecordingIndicator = false;
      });
    }
  }

  Future<void> _createNewChat() async {
     _log("Creating new chat...");
     if (_isLoading) return;
     if (MediaQuery.of(context).size.width < 700 && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
        Navigator.of(context).pop();
        await Future.delayed(const Duration(milliseconds: 250));
     }
     _setupInitialChatState();
     await _loadChatSessionsForSidebar();
     _textController.clear();
     _log("New chat created. Session ID is now null.");
  }

  /// Extracts a short topic from the first 6 words of the user text.
  /// Free and instant — no extra API call needed.
  String _generateTopicLocally(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final words = cleaned.split(' ').where((w) => w.isNotEmpty).toList();
    final topic = words.take(6).join(' ');
    return topic.length > 50 ? '${topic.substring(0, 47)}...' : topic;
  }

  /// Trims oldest entries from AI history when it exceeds [_maxHistoryLength].
  void _trimChatHistory() {
    while (_chatHistoryForAI.length > _maxHistoryLength) {
      _chatHistoryForAI.removeAt(0);
    }
  }

  bool _shouldUseAcademicResearch(String text) {
    if (!_useWebReferences) return false;
    final query = text.trim().toLowerCase();
    if (query.isEmpty) return false;
    if (_studyMode == StudyMode.researchAssistant ||
        _studyMode == StudyMode.academicWriting ||
        _studyMode == StudyMode.literatureReview) {
      return true;
    }
    const keywords = [
      'reference', 'references', 'citation', 'citations', 'paper', 'journal',
      'research', 'study', 'studies', 'literature', 'doi', 'abstract',
      'source', 'sources', 'evidence', 'academic', 'scholar', 'recent',
    ];
    return keywords.any(query.contains);
  }

  Future<({bool useTool, List<String> queries, String status})> _planAcademicResearch(String text) async {
    final trimmed = text.trim();
    if (!_useWebReferences || trimmed.isEmpty) {
      return (useTool: false, queries: const <String>[], status: 'unavailable');
    }

    final fallbackUseTool = _shouldUseAcademicResearch(trimmed);
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (_model == null || apiKey == null || apiKey.isEmpty) {
      return (
        useTool: fallbackUseTool,
        queries: fallbackUseTool ? <String>[trimmed] : const <String>[],
        status: fallbackUseTool ? 'used' : 'skipped',
      );
    }

    try {
      final availableIds = _availableModels.map((model) => model['id']).whereType<String>().toSet();
      final decisionModelId = availableIds.contains('gemini-3.1-flash-lite-preview')
          ? 'gemini-3.1-flash-lite-preview'
          : _selectedModelId;
      final decisionModel = GenerativeModel(
        model: decisionModelId,
        apiKey: apiKey,
        systemInstruction: Content('system', [
          TextPart('You are a tool router for an academic assistant. Decide whether to call the academic web search tool before answering. Return strict JSON only with keys use_web_tool and queries. Use the tool for current facts, recent information, citations, papers, literature reviews, fact-checking, verification, or when external evidence is needed. Do not use the tool for simple explanations, casual chat, brainstorming, or rewriting when external evidence is unnecessary. If use_web_tool is true, queries must be an array of 1 to 3 concise search-ready queries ordered from best to fallback.'),
        ]),
      );
      final decisionPrompt = [
        'Study mode: ${_studyMode.label}',
        'Grounded academic mode: ${_groundedAcademicMode ? 'on' : 'off'}',
        'User request:',
        trimmed,
        '',
        'Return JSON only. Example:',
        '{"use_web_tool": true, "queries": ["climate change adaptation urban flooding systematic review", "urban flooding climate adaptation review", "urban flood adaptation evidence"]}',
      ].join('\n');
      final response = await decisionModel.generateContent([
        Content('user', [TextPart(decisionPrompt)]),
      ]);
      final parsed = _parseWebToolDecision(response.text ?? '', fallbackQuery: trimmed);
      if (parsed != null) {
        return parsed;
      }
    } catch (e) {
      _log('Web tool decision failed, using fallback heuristic: $e');
    }

    return (
      useTool: fallbackUseTool,
      queries: fallbackUseTool ? <String>[trimmed] : const <String>[],
      status: fallbackUseTool ? 'used' : 'skipped',
    );
  }

  ({bool useTool, List<String> queries, String status})? _parseWebToolDecision(String raw, {required String fallbackQuery}) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    final jsonText = match?.group(0) ?? raw;

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final dynamic flagValue = decoded['use_web_tool'] ?? decoded['useWebTool'];
      final bool useTool = switch (flagValue) {
        true => true,
        false => false,
        String() => flagValue.toLowerCase() == 'true',
        num() => flagValue != 0,
        _ => false,
      };
      final rawQueries = switch (decoded['queries']) {
        List<dynamic> values => values.map((value) => value.toString().trim()).where((value) => value.isNotEmpty).toList(),
        _ => <String>[],
      };
      final fallbackSingle = (decoded['query'] as String?)?.trim();
      final queries = <String>[
        ...rawQueries,
        if (rawQueries.isEmpty && fallbackSingle != null && fallbackSingle.isNotEmpty) fallbackSingle,
        if (useTool && rawQueries.isEmpty && (fallbackSingle == null || fallbackSingle.isEmpty)) fallbackQuery,
      ].take(3).toList();
      return (useTool: useTool, queries: useTool ? queries : const <String>[], status: useTool ? 'used' : 'skipped');
    } catch (_) {
      return null;
    }
  }

  String _buildModeInstruction() {
    switch (_studyMode) {
      case StudyMode.explain:
        return 'Teach in depth. Explain the topic step by step, define important terms, connect ideas logically, use simple examples, point out common misunderstandings, and make the user understand not just the answer but the reasoning behind it.';
      case StudyMode.examPrep:
        return 'Teach for exam performance without becoming shallow. Explain the concept clearly first, then highlight key facts, likely questions, memory aids, and quick recall points.';
      case StudyMode.researchAssistant:
        return 'Act like a research assistant. Analyze evidence in detail, compare studies, explain methods and findings clearly, and surface uncertainty, limitations, and disagreements explicitly.';
      case StudyMode.academicWriting:
        return 'Support academic writing ethically. Improve argument structure, clarity, and citation grounding without enabling cheating or fabricated scholarship.';
      case StudyMode.literatureReview:
        return 'Synthesize themes, methods, gaps, and disagreements across sources in literature-review style.';
      case StudyMode.lifeGuidance:
        return 'Act like a thoughtful life guidance coach. When users share real-life situations, identify the actual problem, relevant pressures, risks, constraints, and options. Give balanced, practical, humane guidance with clear reasoning, tradeoffs, and next steps. Do not be vague or purely motivational.';
    }
  }

  String _buildStructuredAnswerInstruction() {
    return switch (_studyMode) {
      StudyMode.literatureReview => 'Structure responses when helpful using: Research Focus, Themes, Methods, Findings, Contradictions, Gaps, References.',
      StudyMode.lifeGuidance => 'Structure responses when helpful using: Situation Analysis, What Matters Most, Options, Tradeoffs, Recommended Next Steps, What To Watch Out For.',
      StudyMode.academicWriting => 'Structure responses when helpful using: Core Claim, Detailed Analysis, Revisions, Evidence, References, Next Step.',
      _ => 'Structure responses when helpful using: Direct Answer, Step-by-Step Explanation, Example, Key Takeaways, References if used, Next Step. Do not collapse into a short summary when the user needs to learn the topic in depth.',
    };
  }

  String _buildGroundingPrompt({required String userText, required List<AcademicSource> sources}) {
    final sections = <String>[
      '[Assistant Mode]',
      _buildModeInstruction(),
      _buildStructuredAnswerInstruction(),
      'Use ${_citationStyle.toUpperCase()} citation style when references are included.',
    ];

    if (_groundedAcademicMode) {
      sections.add('Grounding mode is ON. Never invent references, authors, publication years, abstracts, or DOIs.');
    }

    if (sources.isNotEmpty) {
      sections.add(_academicSearchService.buildGroundingBlock(
        sources,
        citationStyle: _citationStyle,
        studyMode: _studyMode.label,
      ));
    } else if (_groundedAcademicMode) {
      sections.add('No external academic evidence was retrieved. If the user asked for current scholarly evidence, say what could not be verified.');
    }

    return '${sections.join("\n\n")}\n\n[User Request]\n$userText';
  }

  Future<List<AcademicSource>> _searchAcademicQuery(String query) async {
    if (query.trim().isEmpty) return const [];
    if (mounted) {
      setState(() {
        _isResearching = true;
        _activeResearchQuery = query;
      });
    }
    try {
      final sources = await _academicSearchService.searchSources(query, maxResults: 8);
      _lastResearchQuery = query;
      if (mounted) {
        setState(() {
          final merged = <String, AcademicSource>{
            for (final source in _recentAcademicSources) source.id: source,
          };
          for (final source in sources) {
            merged[source.id] = source.copyWith(isSaved: _savedSourceIds.contains(source.id));
          }
          _recentAcademicSources = merged.values.toList()
            ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
        });
      }
      return sources.map((source) => source.copyWith(isSaved: _savedSourceIds.contains(source.id))).toList();
    } catch (e) {
      _log('Academic search failed: $e');
      return const [];
    } finally {
      if (mounted) {
        setState(() {
          _isResearching = false;
          _activeResearchQuery = null;
        });
      }
    }
  }

  Future<({List<AcademicSource> sources, String status, String? queryText})> _collectAcademicResearch(String query) async {
    final plan = await _planAcademicResearch(query);
    if (!plan.useTool) {
      return (sources: const <AcademicSource>[], status: plan.status, queryText: null);
    }

    final merged = <String, AcademicSource>{};
    final attemptedQueries = <String>[];

    for (final plannedQuery in plan.queries.take(3)) {
      final trimmed = plannedQuery.trim();
      if (trimmed.isEmpty) continue;
      attemptedQueries.add(trimmed);
      final sources = await _searchAcademicQuery(trimmed);
      for (final source in sources) {
        merged[source.id] = source;
      }
      if (merged.length >= 8) {
        break;
      }
    }

    final sortedSources = merged.values.toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

    return (
      sources: sortedSources.take(8).toList(),
      status: sortedSources.isEmpty ? 'used_no_results' : 'used',
      queryText: attemptedQueries.isEmpty ? null : attemptedQueries.join(' | '),
    );
  }

  String _resolveModelIdForTask(String taskKind) {
    if (!_smartRoutingEnabled) return _selectedModelId;
    final availableIds = _availableModels.map((model) => model['id']).whereType<String>().toSet();
    if ((taskKind == 'literature_review' || taskKind == 'fact_check' || taskKind == 'verify_draft' || taskKind == 'deep_explain' || taskKind == 'life_guidance') &&
        availableIds.contains('gemini-3-flash-preview')) {
      return 'gemini-3-flash-preview';
    }
    if (taskKind == 'exam_prep' &&
        availableIds.contains('gemini-3.1-flash-lite-preview')) {
      return 'gemini-3.1-flash-lite-preview';
    }
    return _selectedModelId;
  }

  GenerativeModel _buildModelForTask(String taskKind) {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final modelId = _resolveModelIdForTask(taskKind);
    return GenerativeModel(
      model: modelId,
      apiKey: apiKey,
      systemInstruction: Content('system', [TextPart(systemInstruction)]),
    );
  }

  Future<void> _queueAssistantTask({
    required String visiblePrompt,
    required String aiPrompt,
    required String taskKind,
    List<AcademicSource> sources = const [],
  }) async {
    if (_isLoading || _model == null) return;
    final sessionId = await _ensureSessionExists(visiblePrompt);
    if (sessionId == null) {
      _addErrorMessageToChat('Could not start a session for this task.');
      return;
    }
    final promptMessage = AppChatMessage(
      messageId: _uuid.v4(),
      text: visiblePrompt,
      isUser: true,
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    if (mounted) {
      setState(() {
        _currentChatMessages.add(promptMessage);
        _isLoading = true;
      });
      _scrollToBottom();
    }
    await _saveMessageToDatabase(promptMessage, sessionId, timestamp);
    final content = Content('user', [TextPart(aiPrompt)]);
    _chatHistoryForAI.add(content);
    _trimChatHistory();
    await _getChatbotResponse(content, taskKind: taskKind, researchSources: sources, queryText: visiblePrompt);
  }

  Future<String?> _ensureSessionExists(String topicSource) async {
    if (_currentSessionId != null) return _currentSessionId;
    if (_database == null || !_database!.isOpen) return null;
    final newSessionId = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final topic = _generateTopicLocally(topicSource);
    await _database!.insert(
      'sessions',
      {'id': newSessionId, 'topic': topic, 'last_updated': timestamp},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (mounted) {
      setState(() {
        _currentSessionId = newSessionId;
      });
    }
    await _loadChatSessionsForSidebar();
    return newSessionId;
  }

  Future<void> _factCheckMessage(AppChatMessage message, List<AcademicSource> sources) async {
    final sourceSet = sources.isNotEmpty ? sources : _recentAcademicSources.take(6).toList();
    final prompt = '''Fact-check the previous assistant answer using the evidence below.

Assistant answer:
${message.text ?? ''}

Return:
1. Supported claims
2. Uncertain or weakly supported claims
3. Unsupported claims or overstatements
4. Corrected answer
5. References in $_citationStyle''';
    await _queueAssistantTask(
      visiblePrompt: 'Fact-check the previous answer',
      aiPrompt: _buildGroundingPrompt(userText: prompt, sources: sourceSet),
      taskKind: 'fact_check',
      sources: sourceSet,
    );
  }

  Future<void> _buildLiteratureReview(List<AcademicSource> sources) async {
    if (sources.length < 2) {
      _showSnackbar('Need at least two sources to build a literature review.');
      return;
    }
    final prompt = 'Build a literature review from the provided sources. Group the studies by themes, methods, findings, contradictions, and gaps. End with references in $_citationStyle.';
    await _queueAssistantTask(
      visiblePrompt: 'Build a literature review from current sources',
      aiPrompt: _buildGroundingPrompt(userText: prompt, sources: sources),
      taskKind: 'literature_review',
      sources: sources,
    );
  }

  Future<void> _verifyDraftFromComposer() async {
    final draft = _textController.text.trim();
    if (draft.isEmpty) return;
    final sources = (await _collectAcademicResearch(draft)).sources;
    final prompt = '''Analyze this draft for academic claim support.

Draft:
$draft

Return:
1. Main claims
2. Supported claims with citations
3. Weak or unsupported claims
4. Safer revisions
5. Reference list in $_citationStyle''';
    await _queueAssistantTask(
      visiblePrompt: 'Verify the draft in the composer',
      aiPrompt: _buildGroundingPrompt(userText: prompt, sources: sources),
      taskKind: 'verify_draft',
      sources: sources,
    );
  }

  Future<void> _copySavedReferences() async {
    final saved = _recentAcademicSources.where((source) => _savedSourceIds.contains(source.id)).toList();
    if (saved.isEmpty) {
      _showSnackbar('No saved references yet.');
      return;
    }
    final text = saved.map((source) => source.formatCitation(_citationStyle)).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    _showSnackbar('Saved references copied.');
  }

  List<String> _researchProviderOptions(List<AcademicSource> sources) {
    final providers = sources.map((source) => source.providerLabel).toSet().toList()..sort();
    return ['All', ...providers];
  }

  List<AcademicSource> _filterResearchSources(List<AcademicSource> sources) {
    final query = _researchSearchQuery.trim().toLowerCase();
    return sources.where((source) {
      final providerMatch = _researchProviderFilter == 'All' || source.providerLabel == _researchProviderFilter;
      final savedMatch = !_researchShowSavedOnly || _savedSourceIds.contains(source.id);
      final searchMatch = query.isEmpty ||
          source.title.toLowerCase().contains(query) ||
          source.authorLine.toLowerCase().contains(query) ||
          source.venueLabel.toLowerCase().contains(query);
      return providerMatch && savedMatch && searchMatch;
    }).toList();
  }

  String _buildReferenceExportContent(List<AcademicSource> sources, String format) {
    switch (format) {
      case 'markdown':
        return [
          '# BasoChat App References',
          '',
          'Citation style: $_citationStyle',
          '',
          ...sources.map((source) => source.toMarkdownCitation(_citationStyle)),
        ].join('\n');
      case 'json':
        return const JsonEncoder.withIndent('  ')
            .convert(sources.map((source) => source.toExportMap(_citationStyle)).toList());
      case 'bibtex':
        return sources.map((source) => source.toBibTex()).join('\n\n');
      case 'txt':
      default:
        return sources.map((source) => source.formatCitation(_citationStyle)).join('\n\n');
    }
  }

  Future<void> _exportSavedReferences({String format = 'txt'}) async {
    final saved = _recentAcademicSources.where((source) => _savedSourceIds.contains(source.id)).toList();
    if (saved.isEmpty) {
      _showSnackbar('No saved references to export.');
      return;
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final extension = switch (format) {
      'markdown' => 'md',
      'json' => 'json',
      'bibtex' => 'bib',
      _ => 'txt',
    };
    final file = File(p.join(docsDir.path, 'basochatapp_references_${DateTime.now().millisecondsSinceEpoch}.$extension'));
    final content = _buildReferenceExportContent(saved, format);
    await file.writeAsString(content);
    _showSnackbar('References exported to ${file.path}');
  }

  Future<void> _showExportOptions() async {
    final format = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF0D1826),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('Export References', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _exportOptionTile(ctx, 'txt', 'Plain text', 'Simple citation list'),
            _exportOptionTile(ctx, 'markdown', 'Markdown', 'Readable notes and reference sections'),
            _exportOptionTile(ctx, 'json', 'JSON', 'Structured export for other tools'),
            _exportOptionTile(ctx, 'bibtex', 'BibTeX', 'Reference-manager friendly format'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (format != null) {
      await _exportSavedReferences(format: format);
    }
  }

  Widget _exportOptionTile(BuildContext context, String value, String title, String subtitle) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF8BA3B0))),
      trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF64D2FF)),
      onTap: () => Navigator.pop(context, value),
    );
  }

  void _showResearchHub() {
    final saved = _recentAcademicSources.where((source) => _savedSourceIds.contains(source.id)).toList();
    final providerOptions = _researchProviderOptions(_recentAcademicSources);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1826),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredSources = _filterResearchSources(_recentAcademicSources);
            final filteredSaved = _filterResearchSources(saved);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.86,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Research Hub', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          if (_isResearching)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            Text(
                              _lastResearchQuery == null ? 'Evidence collected in this session.' : 'Latest scholarly query: $_lastResearchQuery',
                              style: const TextStyle(color: Color(0xFF8BA3B0)),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(child: _researchStatCard('Session Sources', '${_recentAcademicSources.length}', Icons.library_books_outlined)),
                                const SizedBox(width: 10),
                                Expanded(child: _researchStatCard('Saved', '${saved.length}', Icons.bookmark_rounded)),
                                const SizedBox(width: 10),
                                Expanded(child: _researchStatCard('Providers', '${providerOptions.length - 1}', Icons.hub_outlined)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: saved.length > 1 ? () => _buildLiteratureReview(saved) : null,
                                  icon: const Icon(Icons.auto_stories_outlined, size: 16),
                                  label: const Text('Review saved'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _copySavedReferences,
                                  icon: const Icon(Icons.content_copy_rounded, size: 16),
                                  label: const Text('Copy'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _showExportOptions,
                                  icon: const Icon(Icons.download_rounded, size: 16),
                                  label: const Text('Export'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              onChanged: (value) => setModalState(() => _researchSearchQuery = value),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Search titles, authors, or journals',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _researchSearchQuery.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () => setModalState(() => _researchSearchQuery = ''),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 38,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: providerOptions.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final provider = providerOptions[index];
                                  final selected = provider == _researchProviderFilter;
                                  return ChoiceChip(
                                    label: Text(provider),
                                    selected: selected,
                                    onSelected: (_) => setModalState(() => _researchProviderFilter = provider),
                                    selectedColor: const Color(0xFF0F5244),
                                    backgroundColor: const Color(0xFF111E2E),
                                    labelStyle: TextStyle(color: selected ? const Color(0xFF00C9A7) : Colors.white70),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _researchShowSavedOnly,
                              onChanged: (value) => setModalState(() => _researchShowSavedOnly = value),
                              title: const Text('Show saved references only', style: TextStyle(color: Colors.white)),
                              subtitle: Text(
                                _researchShowSavedOnly ? 'Filtered to your saved evidence.' : 'Showing all evidence retrieved this session.',
                                style: const TextStyle(color: Color(0xFF8BA3B0)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('Saved Reference Shelf', style: TextStyle(color: Color(0xFF64D2FF), fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 235,
                              child: filteredSaved.isEmpty
                                  ? const Center(child: Text('No saved references match the current filters.', style: TextStyle(color: Color(0xFF8BA3B0))))
                                  : ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: filteredSaved.length,
                                      itemBuilder: (context, index) => AcademicSourceCard(
                                        source: filteredSaved[index],
                                        citationStyle: _citationStyle,
                                        isSaved: _savedSourceIds.contains(filteredSaved[index].id),
                                        onToggleSaved: () async {
                                          await _toggleSavedSource(filteredSaved[index]);
                                          setModalState(() {});
                                        },
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 14),
                            Text('Evidence Browser (${filteredSources.length})', style: const TextStyle(color: Color(0xFF64D2FF), fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            if (filteredSources.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(child: Text('No sources match the current filters.', style: TextStyle(color: Color(0xFF8BA3B0)))),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredSources.length,
                                itemBuilder: (context, index) {
                                  final source = filteredSources[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF111E2E),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: const Color(0xFF1E3A54)),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        title: Text(source.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('${source.authorLine} • ${source.year?.toString() ?? 'n.d.'} • ${source.providerLabel}', style: const TextStyle(color: Color(0xFF8BA3B0))),
                                              const SizedBox(height: 4),
                                              Text(source.venueLabel, style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                        trailing: IconButton(
                                          icon: Icon(_savedSourceIds.contains(source.id) ? Icons.bookmark_rounded : Icons.bookmark_add_outlined, color: const Color(0xFF00C9A7)),
                                          onPressed: () async {
                                            await _toggleSavedSource(source);
                                            setModalState(() {});
                                          },
                                        ),
                                        onTap: () => showDialog<void>(
                                          context: context,
                                          builder: (_) => Dialog(
                                            backgroundColor: Colors.transparent,
                                            child: AcademicSourceCard(
                                              source: source,
                                              citationStyle: _citationStyle,
                                              isSaved: _savedSourceIds.contains(source.id),
                                              onToggleSaved: () async {
                                                await _toggleSavedSource(source);
                                                Navigator.pop(context);
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _researchStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3A54)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF64D2FF)),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFF8BA3B0), fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _getChatbotResponse(
    Content userContent, {
    String taskKind = 'chat',
    List<AcademicSource> researchSources = const [],
    String? webToolStatus,
    String? queryText,
  }) async {
    if (_model == null) {
      _log("Error: AI Model not initialized in _getChatbotResponse.");
      _addErrorMessageToChat("Internal error occured (lack initialization). Please try again later or contact us at: basobasosoftwares@gmail.com if the problem persist.");
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (_chatHistoryForAI.isEmpty) {
      _log("Error: AI history is empty before sending.");
      _addErrorMessageToChat("Internal error occured (history). Please try again later or contact us at: basobasosoftwares@gmail.com if the problem persist.");
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _log("Starting AI response stream...");
    final placeholderText = "...";
    int botMessageIndex = -1;
    final String placeholderMessageId = _uuid.v4();
    final initialBotMessage = AppChatMessage(
      messageId: placeholderMessageId,
      text: placeholderText,
      isUser: false);
    if (mounted) {
      setState(() {
        _currentChatMessages.add(initialBotMessage);
        botMessageIndex = _currentChatMessages.length - 1;
        _isLoading = true;
        _isStreamingResponse = true;
      });
      _scrollToBottom();
    }
    if (botMessageIndex == -1) {
       _log("Error: Cannot add placeholder message, widget not mounted?");
       if (mounted) setState(() => _isLoading = false);
       return;
    }

    StringBuffer textBuffer = StringBuffer();
    Uint8List? receivedImageBytes;
    String? receivedImageMimeType;
    bool streamBlocked = false;
    bool receivedAnyContent = false;
    Content? botContentForHistory;
    DateTime lastStreamUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    bool streamCancelled = false;

    void pushStreamUpdate({bool force = false}) {
      if (!mounted || botMessageIndex < 0 || botMessageIndex >= _currentChatMessages.length) {
        return;
      }
      final now = DateTime.now();
      if (!force && now.difference(lastStreamUiUpdate).inMilliseconds < 90) {
        return;
      }
      lastStreamUiUpdate = now;
      setState(() {
        if (receivedImageBytes != null) {
          _currentChatMessages[botMessageIndex] = AppChatMessage(
            messageId: placeholderMessageId,
            imageBytes: receivedImageBytes,
            isUser: false,
          );
        } else if (textBuffer.isNotEmpty) {
          _currentChatMessages[botMessageIndex] = AppChatMessage(
            messageId: placeholderMessageId,
            text: "${textBuffer.toString()}...",
            isUser: false,
          );
        }
      });
    }

    try {
      final modelForTask = _buildModelForTask(taskKind);
      final Stream<GenerateContentResponse> responseStream =
          modelForTask.generateContentStream(_chatHistoryForAI);

      _cancelStreamingResponseRequested = false;
      _responseStreamDoneCompleter = Completer<void>();
      _responseStreamSubscription = responseStream.listen(
        (chunk) {
          if (chunk.promptFeedback?.blockReason != null) {
            streamBlocked = true;
            final reason = chunk.promptFeedback!.blockReason;
            _log("Stream blocked by safety settings. Reason: $reason");
            if (mounted && botMessageIndex < _currentChatMessages.length && botMessageIndex >= 0) {
              final blockedMessageText = "⚠️ Response blocked ($reason).";
              setState(() {
                _currentChatMessages[botMessageIndex] = AppChatMessage(
                  messageId: placeholderMessageId,
                  text: blockedMessageText,
                  isUser: false,
                );
              });
              botContentForHistory = Content("model", [TextPart(blockedMessageText)]);
            }
            _addErrorMessageToChat("Response blocked due to safety settings (Reason: $reason).");
            _responseStreamDoneCompleter?.complete();
            return;
          }

          final candidate = chunk.candidates.firstOrNull;
          final content = candidate?.content;
          final parts = content?.parts;

          if (parts != null && parts.isNotEmpty) {
            receivedAnyContent = true;
            for (final part in parts) {
              if (part is TextPart) {
                textBuffer.write(part.text);
              } else if (part is DataPart) {
                _log("Received DataPart, MIME: ${part.mimeType}, Size: ${part.bytes.length}");
                receivedImageBytes = part.bytes;
                receivedImageMimeType = part.mimeType;
              }
            }

            pushStreamUpdate();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (error is GenerativeAIException) {
            _log("Generative AI Error during streaming: ${error.message}");
            final errorText = "⚠️ An AI error occurred: ${error.message}";
            if (mounted && botMessageIndex < _currentChatMessages.length && botMessageIndex >= 0) {
              setState(() => _currentChatMessages[botMessageIndex] = AppChatMessage(
                messageId: placeholderMessageId,
                text: errorText,
                isUser: false,
              ));
            }
            botContentForHistory = Content("model", [TextPart(errorText)]);
            _addErrorMessageToChat("An AI error occurred.");
          } else {
            _log("Error during streaming response: $error");
            final errorText = "⚠️ An unexpected error occurred.";
            if (mounted && botMessageIndex < _currentChatMessages.length && botMessageIndex >= 0) {
              setState(() => _currentChatMessages[botMessageIndex] = AppChatMessage(
                messageId: placeholderMessageId,
                text: errorText,
                isUser: false,
              ));
            }
            botContentForHistory = Content("model", [TextPart(errorText)]);
            _addErrorMessageToChat("An unexpected error occurred while getting the response.");
          }
          if (!(_responseStreamDoneCompleter?.isCompleted ?? true)) {
            _responseStreamDoneCompleter?.complete();
          }
        },
        onDone: () {
          if (!(_responseStreamDoneCompleter?.isCompleted ?? true)) {
            _responseStreamDoneCompleter?.complete();
          }
        },
        cancelOnError: false,
      );

      await _responseStreamDoneCompleter!.future;
      streamCancelled = _cancelStreamingResponseRequested;
      _responseStreamSubscription = null;
      _responseStreamDoneCompleter = null;

      _log("AI response stream finished.");
      pushStreamUpdate(force: true);

      if (streamCancelled) {
        final stoppedText = textBuffer.toString().trim();
        final finalStoppedText = stoppedText.isEmpty ? 'Generation stopped.' : '$stoppedText\n\n[Generation stopped]';
        botContentForHistory = Content("model", [TextPart(finalStoppedText)]);
      } else if (!streamBlocked) {
        if (receivedImageBytes != null) {
          _log("Final content is IMAGE (${receivedImageBytes!.length} bytes)");
          botContentForHistory = Content("model", [DataPart(receivedImageMimeType ?? 'application/octet-stream', receivedImageBytes!)]);
        } else if (textBuffer.isNotEmpty) {
          final fullResponseText = textBuffer.toString();
          _log("Final content is TEXT (${fullResponseText.length} chars)");
          botContentForHistory = Content("model", [TextPart(fullResponseText)]);
        } else if (receivedAnyContent) {
           _log("Stream finished with empty or unhandled parts.");
           botContentForHistory = Content("model", [TextPart("AI returned an empty or uninterpretable response.")]);
        } else {
           _log("Stream finished with no content received.");
           botContentForHistory = Content("model", [TextPart("⚠️ AI returned no response data.")]);
        }
      }
    } catch (e) {
      _log("Error preparing streaming response: $e");
      final errorText = "⚠️ An unexpected error occurred.";
      if (mounted && botMessageIndex < _currentChatMessages.length && botMessageIndex >= 0) {
        setState(() => _currentChatMessages[botMessageIndex] = AppChatMessage(
          messageId: placeholderMessageId,
          text: errorText,
          isUser: false,
        ));
      }
      botContentForHistory = Content("model", [TextPart(errorText)]);
      _addErrorMessageToChat("An unexpected error occurred while getting the response.");
    } finally {
      await _responseStreamSubscription?.cancel();
      _responseStreamSubscription = null;
      if (!(_responseStreamDoneCompleter?.isCompleted ?? true)) {
        _responseStreamDoneCompleter?.complete();
      }
      _responseStreamDoneCompleter = null;
      if (mounted && botMessageIndex < _currentChatMessages.length && botMessageIndex >= 0) {
        AppChatMessage finalBotUiMessage;
        if (receivedImageBytes != null && botContentForHistory?.parts.whereType<DataPart>().isNotEmpty == true) {
          finalBotUiMessage = AppChatMessage(messageId: placeholderMessageId, imageBytes: receivedImageBytes, isUser: false);
        } else {
          String finalTextForUi = textBuffer.toString();
          if (streamCancelled) {
             finalTextForUi = botContentForHistory?.parts.whereType<TextPart>().firstOrNull?.text ?? 'Generation stopped.';
          } else if (streamBlocked) {
             finalTextForUi = _currentChatMessages[botMessageIndex].text ?? "⚠️ Response blocked.";
          } else if (botContentForHistory?.parts.whereType<TextPart>().isNotEmpty == true) {
             finalTextForUi = botContentForHistory!.parts.whereType<TextPart>().first.text;
          } else if (textBuffer.isEmpty && receivedImageBytes == null) {
             finalTextForUi = _currentChatMessages[botMessageIndex].text ?? "⚠️ AI response unclear.";
          }
          finalBotUiMessage = AppChatMessage(messageId: placeholderMessageId, text: finalTextForUi, isUser: false);
        }
        setState(() { _currentChatMessages[botMessageIndex] = finalBotUiMessage; });

        if (finalBotUiMessage.text != null && _currentSessionId != null) {
          final resolvedWebToolStatus = webToolStatus ?? (researchSources.isNotEmpty ? 'used' : null);
          await _saveMessageToDatabase(
            finalBotUiMessage,
            _currentSessionId!,
            DateTime.now().millisecondsSinceEpoch,
            webToolStatus: resolvedWebToolStatus,
          );
          if (resolvedWebToolStatus != null && mounted) {
            setState(() {
              _webToolStatusByMessageId[finalBotUiMessage.messageId] = resolvedWebToolStatus;
              if (resolvedWebToolStatus.startsWith('used')) {
                _webToolMessageIds.add(finalBotUiMessage.messageId);
              }
            });
          }
          if (researchSources.isNotEmpty) {
            await _saveAcademicSourcesToDatabase(
              researchSources,
              _currentSessionId!,
              messageId: finalBotUiMessage.messageId,
              queryText: queryText,
            );
            if (mounted) {
              setState(() {
                _messageSources[finalBotUiMessage.messageId] = researchSources
                    .map((source) => source.copyWith(
                          messageId: finalBotUiMessage.messageId,
                          queryText: queryText,
                          isSaved: _savedSourceIds.contains(source.id),
                        ))
                    .toList();
              });
            }
          }
        } else if (finalBotUiMessage.imageBytes != null) {
           _log("Warning: Image message received from AI but not saved to database in _getChatbotResponse.");
        }
      }

      if (botContentForHistory != null) {
        _chatHistoryForAI.add(botContentForHistory!);
      } else {
        if (_chatHistoryForAI.isNotEmpty && _chatHistoryForAI.last.role == "user") {
          _log("CRITICAL: botContentForHistory was null in finally. Adding generic model error to AI history.");
          _chatHistoryForAI.add(Content("model", [TextPart("⚠️ AI response processing encountered an unhandled state.")]));
        }
      }
      _trimChatHistory();
      if (mounted) { setState(() { _isLoading = false; _isStreamingResponse = false; }); }
      _log("Streaming process finished. Loading state set to false. AI History length: ${_chatHistoryForAI.length}");
    }
  }

  void _addErrorMessageToChat(String userFriendlyMessage) {
    if (mounted) {
      setState(() {
        if (_currentChatMessages.isEmpty || _currentChatMessages.last.text != "⚠️ $userFriendlyMessage") {
          _currentChatMessages.add(AppChatMessage(
            messageId: _uuid.v4(),
            text: "⚠️ $userFriendlyMessage", isUser: false));
        }
        _isLoading = false;
        if (_isListening) {
           _log("Error occurred, stopping speech recognition.");
           _stopListening(cancel: true);
        }
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendMessage() async {
    final textFromField = _textController.text.trim();

    if ((textFromField.isEmpty && _currentAttachments.isEmpty) || _isLoading || _isListening || _selectedMessageIndex != null) {
      _log("Send condition not met (text empty and no attachments, or loading/listening/selected)...");
      if (_isOffline && (textFromField.isNotEmpty || _currentAttachments.isNotEmpty)) {
        // Allow queuing if offline but content exists
      } else {
        return;
      }
    }
    if (_model == null && !_isOffline) {
       _addErrorMessageToChat("Cannot send message: AI Model is not initialized.");
       return;
    }

    if (mounted) setState(() => _isLoading = true);
    final currentText = _textController.text;
    _textController.clear();
    FocusScope.of(context).unfocus();

    final attachmentsForSend = List<AppAttachment>.from(_currentAttachments);
    final payload = await _buildSubmissionPayload(rawText: currentText, attachments: attachmentsForSend);
    final parts = payload.parts;
    if (parts.isEmpty) {
      _log("No content (text or valid attachments) to send to AI.");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _editingMessageId = null;
        });
      }
      return;
    }

    final editingMessageId = _editingMessageId;
    if (editingMessageId != null) {
      final editIndex = _currentChatMessages.indexWhere((message) => message.messageId == editingMessageId);
      if (editIndex == -1) {
        if (mounted) {
          setState(() => _editingMessageId = null);
        }
      } else {
        await _removeMessagesStartingAt(editIndex);
        _rebuildAiHistory(endExclusive: editIndex);
      }
    }

    final messageId = _uuid.v4();
    final List<String>? currentMessageAttachmentIds = attachmentsForSend.isNotEmpty
        ? attachmentsForSend.map((a) => a.id).toList()
        : null;
    final messageTextToSend = payload.messageTextToSend;

    final userMessage = AppChatMessage(
      messageId: messageId,
      text: messageTextToSend.isNotEmpty ? messageTextToSend : null,
      isUser: true,
      isQueued: _isOffline,
      isEdited: editingMessageId != null,
      attachmentIds: currentMessageAttachmentIds
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (mounted) {
      setState(() { _currentChatMessages.add(userMessage); });
      _scrollToBottom();
    }

    String? targetSessionId = _currentSessionId;
    bool isNewSession = false;
    if (targetSessionId == null) {
      isNewSession = true;
      _log("First user message/action, creating new session...");
      targetSessionId = _uuid.v4();
      final topicSource = messageTextToSend.isNotEmpty ? messageTextToSend
                          : (attachmentsForSend.isNotEmpty ? attachmentsForSend.first.originalName : "Chat");
      final topic = _generateTopicLocally(topicSource);
      final newSession = { 'id': targetSessionId, 'topic': topic, 'last_updated': timestamp };

      if (_database != null && _database!.isOpen) {
        try {
          await _database!.insert('sessions', newSession, conflictAlgorithm: ConflictAlgorithm.replace);
          _log("New session created in DB: $targetSessionId, Topic: '$topic'");
          if (mounted) {
            _currentSessionId = targetSessionId;
          }
          if (attachmentsForSend.isNotEmpty) {
            await _saveAttachmentsToDatabase(attachmentsForSend, targetSessionId);
          }
         } catch (e) {
           _log("Error inserting new session into DB: $e");
           _addErrorMessageToChat("Error starting new chat session.");
           if (mounted) setState(() => _isLoading = false);
           return;
        }
      } else {
         _log("Error: Database not available for creating new session.");
         _addErrorMessageToChat("Error starting new chat session.");
         if (mounted) setState(() => _isLoading = false);
         return;
      }
    } else {
      if (attachmentsForSend.isNotEmpty) {
        await _saveAttachmentsToDatabase(attachmentsForSend, targetSessionId);
      }
    }

    await _saveMessageToDatabase(userMessage, targetSessionId, timestamp);
    if (isNewSession) { await _loadChatSessionsForSidebar(); }

    if (_isOffline) {
      if (mounted) {
        setState(() {
         _currentAttachments.clear();
         _editingMessageId = null;
         _isLoading = false;
        });
         _showSnackbar("Message queued. Will send when online.", duration: const Duration(seconds: 3));
      }
      return;
    }

    final userContent = Content("user", parts);
    _chatHistoryForAI.add(userContent);
    _trimChatHistory();
    _log("User content added to _chatHistoryForAI (length: ${_chatHistoryForAI.length})");

    await _getChatbotResponse(
      userContent,
      taskKind: _currentTaskKind(),
      researchSources: payload.researchSources,
      webToolStatus: payload.webToolStatus,
      queryText: payload.webToolQueryText ?? messageTextToSend,
    );

    if (mounted) {
      setState(() {
        _currentAttachments.clear();
        _editingMessageId = null;
      });
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final bool currentlyOffline = !results.contains(ConnectivityResult.wifi) && !results.contains(ConnectivityResult.ethernet) && !results.contains(ConnectivityResult.mobile) && !results.contains(ConnectivityResult.vpn);
    _log("Connectivity changed. Results: $results. Is Offline: $currentlyOffline");

    bool wasOffline = _isOffline;

    if (mounted && _isOffline != currentlyOffline) {
      setState(() => _isOffline = currentlyOffline);
    }

    if (wasOffline && !currentlyOffline) {
      if (mounted) {
        _showSnackbar("Back online! Sending queued messages...", duration: const Duration(seconds: 3), bgColor: Colors.green[700]);
        _sendQueuedMessages();
      }
    } else if (!wasOffline && currentlyOffline) {
      if (mounted) {
        _showSnackbar("You are offline. Messages will be queued.", duration: const Duration(seconds: 4), bgColor: Colors.orange[800]);
        if (_isListening) { _log("Went offline, cancelling speech recognition."); _stopListening(cancel: true); }
      }
    }
  }

  Future<void> _sendQueuedMessages() async {
    if (_isOffline || _isLoading) return;
    if (_database == null || !_database!.isOpen) {
      _log("Cannot send queued messages: DB not available.");
      return;
    }

    _log("Checking for queued messages...");
    List<Map<String, dynamic>> queuedMessagesData;
    try {
      if (_currentSessionId == null) {
        _log("No active session to check for queued messages. Will try to load last session with queued items.");
        final sessionsWithQueue = await _database!.rawQuery(
          'SELECT DISTINCT session_id FROM messages WHERE is_queued = 1 AND is_user = 1 ORDER BY timestamp DESC LIMIT 1'
        );
        if (sessionsWithQueue.isNotEmpty) {
          final sessionIdToLoad = sessionsWithQueue.first['session_id'] as String?;
          if (sessionIdToLoad != null) {
            _log("Found session $sessionIdToLoad with queued messages. Loading it.");
            await _loadChatSession(sessionIdToLoad); // This will set _currentSessionId if successful
            if (_currentSessionId == null) { // Check if loading actually set the session
                 _log("Failed to load session $sessionIdToLoad for queued messages.");
                 return;
            }
          } else { return; } // No session ID found in query result
        } else {
          _log("No sessions found with queued messages.");
          return;
        }
      }

      // _currentSessionId should now be set if a session with queued messages was found and loaded
      queuedMessagesData = await _database!.query(
        'messages',
        where: 'session_id = ? AND is_queued = ? AND is_user = ?',
        whereArgs: [_currentSessionId!, 1, 1], // Use non-null assertion as it should be set
        orderBy: 'timestamp ASC',
      );
    } catch (e) {
      _log("Error fetching queued messages: $e");
      return;
    }

    if (queuedMessagesData.isEmpty) {
      _log("No queued messages found for session $_currentSessionId.");
      return;
    }

    _log("Found ${queuedMessagesData.length} queued message(s) for session $_currentSessionId. Attempting to send...");
    if (mounted) setState(() => _isLoading = true);

    for (final msgData in queuedMessagesData) {
      if (_isOffline) {
        _log("Went offline while sending queued messages. Aborting.");
        _showSnackbar("Connection lost. Pausing queued message sending.", bgColor: Colors.orange[800]);
        break;
      }

      final messageId = msgData['id'] as String;
      final text = msgData['text'] as String?;
      final attachmentIdsJson = msgData['attachment_ids_json'] as String?;
      List<String>? attachmentIds;
      if (attachmentIdsJson != null) {
        attachmentIds = List<String>.from(jsonDecode(attachmentIdsJson));
      }

      _log("Processing queued message ID: $messageId, Text: '$text'");

      final List<Part> parts = [];
      if (text != null && text.isNotEmpty) {
        String textForAI = text;
        if (attachmentIds != null && attachmentIds.isNotEmpty && !text.contains("[System Note:")) {
            final List<String> originalFilenames = [];
            for(String attId in attachmentIds) {
                final attDataList = await _database!.query('session_attachments', columns: ['original_name'], where: 'id = ? AND session_id = ?', whereArgs: [attId, _currentSessionId!]);
                if (attDataList.isNotEmpty) originalFilenames.add("'${attDataList.first['original_name'] as String}'");
            }
            if (originalFilenames.isNotEmpty) {
                textForAI += "\n\n[System Note: Analyze the user's query. If you use information derived from the provided file(s) (${originalFilenames.join(', ')}) to formulate your response, please explicitly list the original filename(s) you referenced under a heading 'References:' at the very end of your response.]";
            }
        }
        parts.add(TextPart(textForAI));
      }


      if (attachmentIds != null && attachmentIds.isNotEmpty) {
        for (String attId in attachmentIds) {
          try {
            final attDataList = await _database!.query('session_attachments', where: 'id = ? AND session_id = ?', whereArgs: [attId, _currentSessionId!]);
            if (attDataList.isNotEmpty) {
              final appAttachment = AppAttachment.fromMap(attDataList.first);
              final fileBytes = await File(appAttachment.storedPath).readAsBytes();
              final mimeType = appAttachment.mimeType ?? lookupMimeType(appAttachment.storedPath) ?? 'application/octet-stream';
              parts.add(DataPart(mimeType, fileBytes));
            }
          } catch (e) { _log("Error processing attachment $attId for queued message $messageId: $e"); }
        }
      }
      if (parts.isEmpty) {
        _log("Skipping queued message $messageId as it has no content parts after reconstruction.");
        await _database!.update('messages', {'is_queued': 0}, where: 'id = ?', whereArgs: [messageId]);
        final uiMessageIndex = _currentChatMessages.indexWhere((m) => m.messageId == messageId);
        if (uiMessageIndex != -1 && mounted) {
          setState(() {
            _currentChatMessages[uiMessageIndex] =
                _currentChatMessages[uiMessageIndex].copyWith(isQueued: false);
          });
        }
        continue;
      }

      final userContent = Content("user", parts);
      _chatHistoryForAI.add(userContent);
      _trimChatHistory();
      _log("Queued Msg Send: Added user content for ${messageId} to AI history. History length: ${_chatHistoryForAI.length}");
      await _getChatbotResponse(userContent);

      await _database!.update('messages', {'is_queued': 0}, where: 'id = ?', whereArgs: [messageId]);
      final uiMessageIndex = _currentChatMessages.indexWhere((m) => m.messageId == messageId);
      if (uiMessageIndex != -1 && mounted) {
        setState(() {
          _currentChatMessages[uiMessageIndex] =
              _currentChatMessages[uiMessageIndex].copyWith(isQueued: false);
        });
      }
      _log("Queued message $messageId sent successfully.");
    }

    if (mounted) setState(() => _isLoading = false);
    if (queuedMessagesData.isNotEmpty && !_isOffline) _showSnackbar("Finished sending queued messages!", duration: const Duration(seconds: 2));
  }


  void _clearSelection() {
    if (_selectedMessageIndex != null || _selectedMessageTextForCopy != null) {
      if (mounted) {
        setState(() { _selectedMessageIndex = null; _selectedMessageTextForCopy = null; });
        _log("Selection cleared.");
      }
    }
  }

  int _lastUserMessageIndex() {
    for (int index = _currentChatMessages.length - 1; index >= 0; index--) {
      if (_currentChatMessages[index].isUser) {
        return index;
      }
    }
    return -1;
  }

  bool _isSyntheticAttachmentLabel(AppChatMessage message) {
    final text = message.text?.trim() ?? '';
    return (message.attachmentIds?.isNotEmpty ?? false) && RegExp(r'^Files? attached:').hasMatch(text);
  }

  Future<List<AppAttachment>> _loadAttachmentsByIds(List<String>? attachmentIds) async {
    if (attachmentIds == null || attachmentIds.isEmpty || _database == null || !_database!.isOpen || _currentSessionId == null) {
      return const [];
    }

    final attachments = <AppAttachment>[];
    for (final attachmentId in attachmentIds) {
      final rows = await _database!.query(
        'session_attachments',
        where: 'id = ? AND session_id = ?',
        whereArgs: [attachmentId, _currentSessionId!],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        attachments.add(AppAttachment.fromMap(rows.first));
      }
    }
    return attachments;
  }

  Content? _historyContentFromMessage(AppChatMessage message) {
    if (message.isUser && message.isQueued) {
      return null;
    }
    if (message.text != null && message.text!.isNotEmpty) {
      return Content(message.isUser ? 'user' : 'model', [TextPart(message.text!)]);
    }
    if (message.isUser && (message.attachmentIds?.isNotEmpty ?? false)) {
      return Content('user', [TextPart('[User sent attachments (ID: ${message.messageId.substring(0, 5)}...)]')]);
    }
    return null;
  }

  void _rebuildAiHistory({int? endExclusive}) {
    final limit = (endExclusive ?? _currentChatMessages.length).clamp(0, _currentChatMessages.length);
    _chatHistoryForAI = [];
    for (int index = 0; index < limit; index++) {
      final content = _historyContentFromMessage(_currentChatMessages[index]);
      if (content != null) {
        _chatHistoryForAI.add(content);
      }
    }
    _trimChatHistory();
  }

  Future<void> _removeMessagesStartingAt(int startIndex) async {
    if (startIndex < 0 || startIndex >= _currentChatMessages.length) {
      return;
    }

    final removedMessages = _currentChatMessages.sublist(startIndex).toList();
    final removedIds = removedMessages.map((message) => message.messageId).toList();

    if (mounted) {
      setState(() {
        _currentChatMessages.removeRange(startIndex, _currentChatMessages.length);
        _messageSources.removeWhere((messageId, _) => removedIds.contains(messageId));
        _webToolMessageIds.removeWhere(removedIds.contains);
        _webToolStatusByMessageId.removeWhere((messageId, _) => removedIds.contains(messageId));
        _recentAcademicSources.removeWhere((source) => source.messageId != null && removedIds.contains(source.messageId));
      });
    }

    if (_database != null && _database!.isOpen && removedIds.isNotEmpty) {
      final placeholders = List.filled(removedIds.length, '?').join(', ');
      await _database!.delete(
        'messages',
        where: 'id IN ($placeholders)',
        whereArgs: removedIds,
      );
    }
  }

  Future<void> _copyQuestionText(AppChatMessage message) async {
    final text = message.text;
    if (text == null || text.isEmpty) {
      _showSnackbar('Nothing to copy for this question.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _showSnackbar('Question copied.');
  }

  Future<void> _startEditingLastUserMessage(AppChatMessage message) async {
    if (_isLoading || _isListening) {
      return;
    }
    final attachments = await _loadAttachmentsByIds(message.attachmentIds);
    final editableText = _isSyntheticAttachmentLabel(message) ? '' : (message.text ?? '');

    if (!mounted) {
      return;
    }

    setState(() {
      _editingMessageId = message.messageId;
      _currentAttachments
        ..clear()
        ..addAll(attachments);
      _textController.text = editableText;
      _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
    });
    FocusScope.of(context).requestFocus(_inputFocusNode);
    _scrollToBottom();
    _showSnackbar('Editing the last question. Send to replace it.');
  }

  void _cancelEditingLastUserMessage() {
    if (_editingMessageId == null) {
      return;
    }
    setState(() {
      _editingMessageId = null;
      _currentAttachments.clear();
      _textController.clear();
    });
    _showSnackbar('Edit cancelled.');
  }

  String _currentTaskKind() {
    return switch (_studyMode) {
      StudyMode.examPrep => 'exam_prep',
      StudyMode.literatureReview => 'literature_review',
      StudyMode.academicWriting => 'verify_draft',
      StudyMode.researchAssistant => 'research',
      StudyMode.explain => 'deep_explain',
      StudyMode.lifeGuidance => 'life_guidance',
    };
  }

  Future<({String messageTextToSend, List<Part> parts, List<AcademicSource> researchSources, String webToolStatus, String? webToolQueryText})> _buildSubmissionPayload({
    required String rawText,
    required List<AppAttachment> attachments,
  }) async {
    final List<Part> parts = [];
    String messageTextToSend = rawText;
    if (messageTextToSend.isEmpty && attachments.isNotEmpty) {
      messageTextToSend = "File${attachments.length > 1 ? 's' : ''} attached: ${attachments.first.originalName}${attachments.length > 1 ? ', ...' : ''}";
    }

    final routingText = rawText.trim().isNotEmpty ? rawText.trim() : messageTextToSend;
    final researchOutcome = await _collectAcademicResearch(routingText);
    final researchSources = researchOutcome.sources;
    String textForAI = messageTextToSend;

    if (textForAI.isNotEmpty) {
      if (attachments.isNotEmpty) {
        final filenames = attachments.map((a) => "'${a.originalName}'").join(', ');
        textForAI += "\n\n[System Note: Analyze the user's query. If you use information derived from the provided file(s) ($filenames) to formulate your response, please explicitly list the original filename(s) you referenced under a heading 'References:' at the very end of your response.]";
      }
      textForAI = _buildGroundingPrompt(userText: textForAI, sources: researchSources);
      if (researchOutcome.status == 'used_no_results') {
        textForAI += '\n\n[Web Tool]\nThe web tool was used for this request but it did not return strong matching academic sources. Do not pretend that evidence was found.';
      } else if (researchOutcome.status == 'skipped') {
        textForAI += '\n\n[Web Tool]\nThe web tool was available but was not needed for this request.';
      } else if (researchOutcome.status == 'unavailable') {
        textForAI += '\n\n[Web Tool]\nThe web tool is unavailable for this request because web references are disabled.';
      }
      parts.add(TextPart(textForAI));
    }

    for (final attachment in attachments) {
      try {
        final fileBytes = await File(attachment.storedPath).readAsBytes();
        final mimeType = attachment.mimeType ?? lookupMimeType(attachment.storedPath) ?? 'application/octet-stream';
        parts.add(DataPart(mimeType, fileBytes));
      } catch (e) {
        _log("Error reading or processing attachment file ${attachment.originalName} (${attachment.storedPath}) for AI: $e");
        _addErrorMessageToChat("Error processing attachment for AI: ${attachment.originalName}.");
      }
    }

    return (
      messageTextToSend: messageTextToSend,
      parts: parts,
      researchSources: researchSources,
      webToolStatus: researchOutcome.status,
      webToolQueryText: researchOutcome.queryText,
    );
  }

  Future<void> _retryLastUserMessage(AppChatMessage message) async {
    if (_isLoading || _isListening || _isOffline) {
      return;
    }
    final lastUserIndex = _lastUserMessageIndex();
    if (lastUserIndex == -1 || _currentChatMessages[lastUserIndex].messageId != message.messageId) {
      return;
    }

    final attachments = await _loadAttachmentsByIds(message.attachmentIds);
    final editableText = _isSyntheticAttachmentLabel(message) ? '' : (message.text ?? '');
    final payload = await _buildSubmissionPayload(rawText: editableText, attachments: attachments);
    if (payload.parts.isEmpty) {
      _showSnackbar('Nothing to retry for this question.');
      return;
    }

    await _removeMessagesStartingAt(lastUserIndex + 1);
    _rebuildAiHistory(endExclusive: lastUserIndex);
    final userContent = Content('user', payload.parts);
    _chatHistoryForAI.add(userContent);
    _trimChatHistory();

    if (mounted) {
      setState(() => _isLoading = true);
    }

    await _getChatbotResponse(
      userContent,
      taskKind: _currentTaskKind(),
      researchSources: payload.researchSources,
      webToolStatus: payload.webToolStatus,
      queryText: payload.webToolQueryText ?? payload.messageTextToSend,
    );
  }

  Future<Directory> _getUploadsDirectory() async {
     final appDocsDir = await getApplicationDocumentsDirectory();
     final uploadsDir = Directory(p.join(appDocsDir.path, 'uploads'));
     if (!await uploadsDir.exists()) {
        try { await uploadsDir.create(recursive: true); _log("Created uploads directory: ${uploadsDir.path}"); }
        catch (e) { _log("Error creating uploads directory: $e"); throw Exception("Could not create uploads directory: $e"); }
     }
     return uploadsDir;
  }

  Future<void> _pickFiles() async {
    if (_isBusyBlockingUi || _isListening) return;
    _log("Attempting to pick files...");
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md', 'csv', 'doc', 'docx', 'rtf', 'jpg', 'jpeg', 'png'],
        withReadStream: false, // Read bytes directly for simplicity here
      );

      if (result != null && result.files.isNotEmpty) {
        _log("Picked ${result.files.length} files.");
        final uploadsDir = await _getUploadsDirectory();
        int addedCount = 0;
        List<AppAttachment> newlyAdded = [];
        if (mounted) setState(() => _isLoading = true);

        for (PlatformFile file in result.files) {
          if (file.path == null) { _log("Warning: Picked file '${file.name}' has no path. Skipping."); _showSnackbar("Skipped file '${file.name}' (Invalid path).", bgColor: Colors.orange[800]); continue; }
          final sourceFile = File(file.path!);
          final uniqueId = _uuid.v4();
          final extension = p.extension(file.name);
          final newFileName = '$uniqueId$extension';
          final destinationPath = p.join(uploadsDir.path, newFileName);
          try {
             _log("Copying '${file.name}' to '$destinationPath'...");
             await sourceFile.copy(destinationPath);
             String? mimeType;
             try {
                // Read a small chunk for MIME detection to avoid loading entire large files into memory
                // Use a fixed size like 256 or 512 bytes for header reading
                final headerBytes = await File(destinationPath).openRead(0, 256).first; // Use 256 bytes
                mimeType = lookupMimeType(destinationPath, headerBytes: headerBytes);
             } catch (mimeError) { _log("Could not read header for MIME type detection for ${file.name}: $mimeError"); mimeType = lookupMimeType(destinationPath); } // Fallback
             _log("File copied. Original: ${file.name}, Stored: $newFileName, MIME: $mimeType");
             final newAttachment = AppAttachment(id: uniqueId, originalName: file.name, storedPath: destinationPath, mimeType: mimeType);
             newlyAdded.add(newAttachment);
             addedCount++;
          } catch (e) {
             _log("Error copying file '${file.name}': $e");
             _showSnackbar("Error processing file: ${file.name}", bgColor: Colors.redAccent);
          }
        }

        if (mounted) {
           setState(() { _currentAttachments.addAll(newlyAdded); _isLoading = false; });
           if (addedCount > 0) { _showSnackbar("$addedCount file(s) attached successfully!"); }
        }
      } else { _log("File picking cancelled or no files selected."); }
    } on PlatformException catch (e) {
      _log("File Picker PlatformException: ${e.code} - ${e.message}");
      _showSnackbar("File picker error. Please try again.", bgColor: Colors.redAccent);
      if (mounted) setState(() => _isLoading = false);
    }
    catch (e) {
      _log("Error picking files: $e");
      if (mounted) {
        _showSnackbar("Error picking files. Please try again.", bgColor: Colors.redAccent);
        setState(() => _isLoading = false);
      }
    }
  }

  void _removeAttachment(int index) {
      if (index < 0 || index >= _currentAttachments.length || _isBusyBlockingUi) return;
     final attachmentToRemove = _currentAttachments[index];
     _log("Attempting to remove attachment: ${attachmentToRemove.originalName}");
     showDialog<bool>(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text("Remove Attachment?"),
         content: Text("Are you sure you want to remove '${attachmentToRemove.originalName}'?"),
         actions: [ TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")), TextButton(style: TextButton.styleFrom(foregroundColor: Colors.redAccent), onPressed: () => Navigator.of(context).pop(true), child: const Text("Remove")), ],
       )
     ).then((confirmed) async {
        if (confirmed == true) {
           _log("User confirmed removal of ${attachmentToRemove.originalName}");
           if (mounted) { setState(() { _currentAttachments.removeAt(index); }); _log("Attachment removed from UI state."); }
           // Deletion from DB and file system should happen if the attachment was *saved*
           // If it's just in the composer (_currentAttachments) and not yet sent/saved with a session,
           // then only the file needs deletion.
           // The current logic might try to delete from DB even if not saved yet, which is harmless but not ideal.
           // A more robust way would be to check if this attachment ID exists in 'session_attachments' for the current session.
           if (_currentSessionId != null && _database != null && _database!.isOpen) {
             try {
                await _database!.delete('session_attachments', where: 'id = ? AND session_id = ?', whereArgs: [attachmentToRemove.id, _currentSessionId]);
                _log("Attachment record deleted from DB for session $_currentSessionId.");
             }
             catch (e) {
                _log("Error deleting attachment record from DB: $e");
             }
          }
          try {
             final file = File(attachmentToRemove.storedPath);
             if (await file.exists()) {
                await file.delete();
                _log("Attachment file deleted from storage: ${attachmentToRemove.storedPath}");
             } else {
                _log("Attachment file not found for deletion: ${attachmentToRemove.storedPath}");
             }
          } catch (e) {
             _log("Error deleting attachment file from storage: $e");
             _showSnackbar("Error deleting attachment file.", bgColor: Colors.redAccent);
          }
          _showSnackbar("Attachment '${attachmentToRemove.originalName}' removed.");
        } else { _log("User cancelled attachment removal."); }
     });
  }

  void _startListening() async {
    _log("--- DEBUG: _startListening entered ---");
    if (!_speechEnabled || _isListening || _isBusyBlockingUi || _isOffline || _isSpeechInitializing) {
      _log("Start listening condition not met (speechEnabled: $_speechEnabled, isListening: $_isListening, isBlocking: $_isBusyBlockingUi, isOffline: $_isOffline, isInitializing: $_isSpeechInitializing)");
        if (!_speechEnabled && mounted && !_isSpeechInitializing) { _showSnackbar("Voice input not available.", bgColor: Colors.orange[800]); }
        else if (_isOffline && mounted) { _showSnackbar("Voice input requires connection.", bgColor: Colors.orange[800]); }
        else if (_isSpeechInitializing && mounted) { _showSnackbar("Voice input is initializing...", bgColor: Colors.grey[600]); }
        return;
    }
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      _log("Microphone permission not granted. Requesting again...");
      if (mounted) _showSnackbar("Microphone permission required.", bgColor: Colors.orange[800]);
      // Optionally, re-trigger permission request here if desired, or guide user to settings.
      // await _requestPermissions(); // This might be too aggressive.
      return;
    }
    _log("Starting speech recognition...");
    _lastRecognizedWords = "";
    try {
       // Using listenFor and pauseFor to manage session duration and silence detection.
       await _speechToText.listen(
         onResult: _onSpeechResult,
         listenFor: const Duration(seconds: 60), // Max duration for a single listen session
         pauseFor: const Duration(seconds: 5),   // Auto-stop if silence for 5s
         localeId: "en_US",                     // Specify locale
         cancelOnError: true,                   // Auto-cancel on error
         partialResults: true,                  // Get intermediate results (good for UI feedback)
       );
       if (mounted) { setState(() { _isListening = true; _showRecordingIndicator = true; }); _log("Speech recognition listening..."); }
    } catch (e) {
      _log("Error starting speech recognition: $e");
      if (mounted) {
        _addErrorMessageToChat("Error starting voice input.");
        setState(() { _isListening = false; _showRecordingIndicator = false; });
      }
    }
  }

  void _stopListening({bool cancel = false}) async {
    if (!_isListening && !_speechToText.isListening) return; // Check both flags
    _log("Stopping speech recognition... Cancel: $cancel");
    try {
      if (cancel) {
        await _speechToText.cancel();
      } else {
        await _speechToText.stop();
      }
    } catch (e) {
      _log("Error stopping/cancelling speech recognition: $e");
    } finally {
      // The status listener should ideally handle setting _isListening and _showRecordingIndicator to false.
      // However, as a fallback or for immediate UI update:
      if (mounted) {
        if (_isListening || _showRecordingIndicator) { // Only update if state needs changing
          setState(() {
            _isListening = false;
            _showRecordingIndicator = false;
          });
        }
        _log("Listening stopped/cancelled. UI state updated (if changed).");
        _lastRecognizedWords = ""; // Clear last recognized words on stop/cancel
      }
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final recognized = result.recognizedWords;
    if (mounted) {
      setState(() {
        _lastRecognizedWords = recognized; // Update for potential intermediate display
        if (result.finalResult && recognized.isNotEmpty) {
          _textController.text = recognized;
          _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: _textController.text.length));
          _log("Final Speech Result: '$recognized'");
        } else if (!result.finalResult && recognized.isNotEmpty) {
          // Optionally update text field with partial results for live feedback
          // _textController.text = recognized;
          // _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
          _log("Partial Speech Result: '$recognized'");
        }
      });


      // If it's the final result and listening is still active (it shouldn't be if pauseFor worked), stop it.
      if (result.finalResult && _isListening) {
         _log("Final result received, ensuring listening is stopped.");
         _stopListening(); // This will also update UI via status listener or finally block
      }
    }
  }

  void _speechStatusListener(String status) {
    _log("Speech Recognition Status: $status");
    if (mounted) {
      final isActuallyListening = status == SpeechToText.listeningStatus;
      if (_isListening != isActuallyListening || _showRecordingIndicator != isActuallyListening) {
        _log("STT status changed listening state. Updating UI. New status: $status, isActuallyListening: $isActuallyListening");
        setState(() {
          _isListening = isActuallyListening;
          _showRecordingIndicator = isActuallyListening;
          if (!isActuallyListening) {
             // If listening stopped and text field is empty but we had some recognized words, populate it.
             if (_textController.text.isEmpty && _lastRecognizedWords.isNotEmpty) {
                _textController.text = _lastRecognizedWords;
                _textController.selection = TextSelection.fromPosition(TextPosition(offset: _textController.text.length));
             }
             _lastRecognizedWords = ""; // Clear after potential use
          }
        });
      }
    }
  }

  void _speechErrorListener(SpeechRecognitionError error) {
    _log("Speech Recognition Error: ${error.errorMsg} (Permanent: ${error.permanent})");
    if (mounted) {
      String userFriendlyMessage;
      switch (error.errorMsg) {
        case 'error_speech_timeout':
          userFriendlyMessage = "Voice input timed out. Tap the mic and speak clearly.";
          break;
        case 'error_no_match':
          userFriendlyMessage = "Couldn't understand speech. Please try again.";
          break;
        case 'error_permission':
           userFriendlyMessage = "Microphone permission denied. Please enable it in settings.";
           // Optionally, attempt to re-request or guide user
           break;
        case 'error_network':
           userFriendlyMessage = "Network error during voice input. Check connection.";
           break;
        case 'error_busy':
           userFriendlyMessage = "Voice recognition service is busy. Please try again shortly.";
           break;
        case 'error_client':
           userFriendlyMessage = "Voice input client error. Please try again.";
           break;
        default:
          userFriendlyMessage = "Voice input error. Please try again."; // Generic for unlisted errors
          _log("Unhandled STT Error: ${error.errorMsg}");
      }
      _showSnackbar(
        userFriendlyMessage,
        bgColor: Colors.orange[800],
        duration: const Duration(seconds: 4)
      );
      // Ensure UI reflects that listening has stopped
      if (_isListening || _showRecordingIndicator) {
        setState(() {
          _isListening = false;
          _showRecordingIndicator = false;
          _lastRecognizedWords = "";
        });
      }
    }
  }

  AppBar _buildAppBar() {
    const Color kAccent = Color(0xFF00C9A7);
    const Color kSurface = Color(0xFF0D1826);

    if (_selectedMessageIndex != null && _selectedMessageTextForCopy != null) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: "Cancel Selection",
          onPressed: _clearSelection,
        ),
        title: const Text("1 message selected", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F5244),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined, color: kAccent),
            tooltip: "Copy Text",
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _selectedMessageTextForCopy!));
              _showSnackbar("Message copied to clipboard");
              _clearSelection();
            },
          ),
        ],
      );
    }

    final currentModelName = _availableModels
      .firstWhere((m) => m['id'] == _selectedModelId, orElse: () => _availableModels.first)['name']!;

    return AppBar(
      backgroundColor: kSurface,
      elevation: 0,
      leading: MediaQuery.of(context).size.width < 700
          ? IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white70),
              tooltip: "Menu",
                onPressed: (_isBusyBlockingUi || _selectedMessageIndex != null || _isListening)
                  ? null
                  : () => _scaffoldKey.currentState?.openDrawer(),
            )
          : null,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF00C9A7), Color(0xFF64D2FF)],
            ).createShader(bounds),
            child: const Text(
              'BasoChat App',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: _showModelSelector,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF111E2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1E3A54)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(currentModelName, style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 11)),
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64D2FF), size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.library_books_outlined, color: Colors.white70),
              if (_recentAcademicSources.isNotEmpty)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          tooltip: 'Research Hub',
          onPressed: _showResearchHub,
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: Colors.white70),
          tooltip: 'Assistant Settings',
          onPressed: _showAssistantSettings,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight((_isOffline ? 24.0 : 0) + (_showRecordingIndicator ? 24.0 : 0)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_showRecordingIndicator)
            Material(
              color: Colors.redAccent[700],
              child: Container(
                height: 24.0,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.mic, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text("Recording... Release to stop", style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
          if (_isOffline)
            Material(
              color: Colors.orange[800],
              child: InkWell(
                onTap: () {
                  if (mounted) {
                    _showSnackbar("Rechecking connection...", duration: const Duration(seconds: 1));
                    Connectivity().checkConnectivity().then(_updateConnectionStatus);
                  }
                },
                child: Container(
                  height: 24.0,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.signal_wifi_off_outlined, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text("Offline - Tap to recheck connection", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildSidebarContent() {
    const Color kAccent = Color(0xFF00C9A7);
    const Color kSidebar = Color(0xFF0B1220);
    const Color kBorder = Color(0xFF1E3A54);
    const String meetoshareUrl = 'https://meet2share.com/';

    return Container(
      color: kSidebar,
      child: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF00C9A7), Color(0xFF0097A7)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('BasoChat App', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFF0F5244), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    _availableModels.firstWhere((m) => m['id'] == _selectedModelId, orElse: () => _availableModels.first)['name']!,
                    style: const TextStyle(color: kAccent, fontSize: 10),
                  ),
                ),
              ]),
            ]),
          ),
          // New Chat button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: GestureDetector(
              onTap: _isLoading ? null : _createNewChat,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: _isLoading
                      ? null
                      : const LinearGradient(colors: [Color(0xFF00C9A7), Color(0xFF0097A7)]),
                  color: _isLoading ? const Color(0xFF111E2E) : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: _isLoading ? Colors.grey : Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text('New Chat', style: TextStyle(color: _isLoading ? Colors.grey : Colors.white, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: kBorder, height: 1),
          // Session list
          Expanded(
            child: _chatSessionsForSidebar.isEmpty
                ? const Center(child: Text("No chat history yet.", style: TextStyle(color: Colors.grey), textAlign: TextAlign.center))
                : ListView.builder(
                    itemCount: _chatSessionsForSidebar.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final session = _chatSessionsForSidebar[index];
                      final sessionId = session['id'] as String?;
                      final topic = session['topic'] as String? ?? 'Chat';
                      if (sessionId == null) return const SizedBox.shrink();
                      final bool isSelected = sessionId == _currentSessionId;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF0F2A3A) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected ? Border.all(color: kBorder) : null,
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.chat_bubble_outline_rounded, size: 16,
                              color: isSelected ? kAccent : Colors.grey[500]),
                          title: Text(topic, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: isSelected ? Colors.white : Colors.grey[300],
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, fontSize: 13)),
                          onTap: () => _loadChatSession(sessionId),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.grey[600]),
                            tooltip: "Delete",
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            onPressed: _isLoading ? null : () => _deleteSingleSession(sessionId, topic),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Divider(color: kBorder, height: 1),
          // Footer links
            _sidebarLink(Icons.library_books_outlined, "Research Hub", _showResearchHub),
            _sidebarLink(Icons.tune_rounded, "Assistant Settings", _showAssistantSettings),
          _sidebarLink(Icons.delete_sweep_outlined, "Clear All History",
              (_isLoading || _chatSessionsForSidebar.isEmpty || _isListening) ? null : _clearChatHistory),
          _sidebarLink(Icons.link_outlined, "Learn More", () => _launchUrl(meetoshareUrl, context)),
          _sidebarLink(Icons.assignment_outlined, "Assignment Help", () => _launchUrl(meetoshareUrl, context)),
          _sidebarLink(Icons.school_outlined, "Dissertation Help", () => _launchUrl(meetoshareUrl, context)),
          _sidebarLink(Icons.forum_outlined, "Discussion", () => _launchUrl(meetoshareUrl, context)),
          _sidebarLink(Icons.local_library_outlined, "Library", () => _launchUrl(meetoshareUrl, context)),
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
            child: Text("by BASOBASO SOFTWARE", style: TextStyle(fontSize: 10, color: Colors.grey[600]), textAlign: TextAlign.center),
          ),
        ]),
      ),
    );
  }

  Widget _sidebarLink(IconData icon, String label, VoidCallback? onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18, color: Colors.grey[500]),
      title: Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
      onTap: onTap,
    );
  }

   Widget _buildAttachmentChips() {
     if (_currentAttachments.isEmpty) { return const SizedBox.shrink(); }
     return Padding(
       padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 4.0, bottom: 0),
       child: Wrap(
         spacing: 6.0, runSpacing: 0.0,
         children: List<Widget>.generate(_currentAttachments.length, (index) {
           final attachment = _currentAttachments[index];
           return Chip(
             label: Text(attachment.originalName, overflow: TextOverflow.ellipsis),
             labelPadding: const EdgeInsets.only(left: 8.0),
             padding: EdgeInsets.zero,
             avatar: const Icon(Icons.attach_file, size: 16, color: Color(0xFF00C9A7)),
             backgroundColor: const Color(0xFF111E2E),
             side: const BorderSide(color: Color(0xFF1E3A54)),
             labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF64D2FF)),
             deleteIcon: const Icon(Icons.cancel, size: 18),
             deleteIconColor: const Color(0xFF64D2FF),
             onDeleted: _isBusyBlockingUi || _isListening ? null : () => _removeAttachment(index),
             materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
             visualDensity: VisualDensity.compact,
           );
         }),
       ),
     );
   }

   Widget _buildResearchToolbar() {
      final canVerifyDraft = _studyMode == StudyMode.academicWriting && _textController.text.trim().isNotEmpty && !_isLoading;
      return Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _toolbarChip(Icons.school_outlined, _studyMode.shortLabel, _showAssistantSettings),
            _toolbarChip(Icons.format_quote_outlined, _citationStyle, _showAssistantSettings),
            _toolbarChip(
              _useWebReferences ? Icons.public_rounded : Icons.public_off_rounded,
              _useWebReferences ? 'Web refs on' : 'Web refs off',
              () => _setUseWebReferences(!_useWebReferences),
              active: _useWebReferences,
            ),
            _toolbarChip(
              Icons.library_books_outlined,
              _recentAcademicSources.isEmpty ? 'Sources' : 'Sources ${_recentAcademicSources.length}',
              _showResearchHub,
              active: _recentAcademicSources.isNotEmpty,
            ),
            if (canVerifyDraft)
              _toolbarChip(Icons.fact_check_outlined, 'Verify draft', _verifyDraftFromComposer, active: true),
            if (_isResearching)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF111E2E),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF1E3A54)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Web tool in use', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            if (_isResearching && _activeResearchQuery != null)
              Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF111E2E),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF1E3A54)),
                ),
                child: Text(
                  'Query: ${_activeResearchQuery!}',
                  style: const TextStyle(color: Color(0xFF8BA3B0), fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
   }

   Widget _toolbarChip(IconData icon, String label, VoidCallback onTap, {bool active = false}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF0F5244) : const Color(0xFF111E2E),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? const Color(0xFF00C9A7) : const Color(0xFF1E3A54)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? const Color(0xFF00C9A7) : const Color(0xFF64D2FF)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: active ? const Color(0xFF00C9A7) : Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
   }

   Widget _buildTextInputArea() {
      const Color kAccent = Color(0xFF00C9A7);
      const Color kInputBg = Color(0xFF111E2E);
      const Color kBorder = Color(0xFF1E3A54);
      const Color kAreaBg = Color(0xFF0D1826);

      final bool canSend = !_isLoading && !_isListening && _selectedMessageIndex == null &&
          !_isSpeechInitializing && (_textController.text.trim().isNotEmpty || _currentAttachments.isNotEmpty);
      final bool canStartListening = !_isSpeechInitializing && !_isBusyBlockingUi && !_isOffline && _speechEnabled && !_isListening;

      String micTooltip;
      if (_isSpeechInitializing) micTooltip = "Initializing voice input...";
      else if (_isListening) micTooltip = "Tap to Stop Recording";
      else if (!_speechEnabled) micTooltip = "Voice input unavailable";
      else if (_isOffline) micTooltip = "Voice input requires connection";
      else if (_isBusyBlockingUi) micTooltip = "Processing...";
      else if (_isStreamingResponse) micTooltip = "You can record while the reply is streaming";
      else micTooltip = "Tap to Record Voice";

      return Container(
        decoration: BoxDecoration(
          color: kAreaBg,
          border: Border(top: BorderSide(color: kBorder, width: 0.5)),
        ),
        padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 12.0, top: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_editingMessageId != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2A3A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E3A54)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, color: Color(0xFF00C9A7), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Editing your last question. Send to replace it.',
                        style: TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                    TextButton(
                      onPressed: _cancelEditingLastUserMessage,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            _buildAttachmentChips(),
            _buildResearchToolbar(),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attach button
                _inputIconButton(
                  icon: Icons.add_circle_outline_rounded,
                  tooltip: "Attach File",
                  onPressed: (_isBusyBlockingUi || _isListening) ? null : _pickFiles,
                ),
                // Mic button
                _inputIconButton(
                  icon: _isSpeechInitializing
                      ? Icons.mic_none
                      : (_isListening ? Icons.mic_off_rounded : Icons.mic_none_outlined),
                  tooltip: micTooltip,
                  color: _isListening ? Colors.redAccent : null,
                  onPressed: _isSpeechInitializing
                      ? null
                      : (canStartListening ? _startListening : (_isListening ? _stopListening : null)),
                ),
                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kInputBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _isListening ? Colors.redAccent.withOpacity(0.5) : kBorder),
                    ),
                    child: TextField(
                      focusNode: _inputFocusNode,
                      controller: _textController,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _isOffline
                            ? "Offline — messages will be queued"
                            : (_isListening ? "Listening..." : (_isSpeechInitializing ? "Initializing voice..." : "Ask a question...")),
                        hintStyle: const TextStyle(color: Color(0xFF4A6580), fontSize: 14),
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                      ),
                      onSubmitted: canSend ? (_) => _sendMessage() : null,
                      textInputAction: TextInputAction.send,
                      enabled: !_isListening && _selectedMessageIndex == null && !_isSpeechInitializing,
                      onChanged: (_) { if (mounted) setState(() {}); },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: _isStreamingResponse
                        ? null
                        : canSend
                        ? const LinearGradient(colors: [Color(0xFF00C9A7), Color(0xFF0097A7)])
                        : null,
                    color: _isStreamingResponse
                        ? Colors.redAccent
                        : canSend
                            ? null
                            : const Color(0xFF111E2E),
                    shape: BoxShape.circle,
                    border: Border.all(color: _isStreamingResponse ? Colors.redAccent : (canSend ? kAccent : kBorder)),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isStreamingResponse ? Icons.stop_rounded : Icons.send_rounded,
                      size: 20,
                      color: _isStreamingResponse ? Colors.white : (canSend ? Colors.white : const Color(0xFF2A4A60)),
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: _isStreamingResponse ? "Stop Generating" : "Send Message",
                    onPressed: _isStreamingResponse ? _stopGeneratingResponse : (canSend ? _sendMessage : null),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
   }

  Widget _inputIconButton({required IconData icon, required String tooltip, VoidCallback? onPressed, Color? color}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 4, left: 2),
          child: Icon(icon, size: 26, color: color ?? (onPressed != null ? Colors.grey[400] : Colors.grey[700])),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isLargeScreen = screenWidth >= 700;
    final int lastUserIndex = _lastUserMessageIndex();

     Widget chatList = ListView.builder(
       controller: _chatScrollController,
       padding: const EdgeInsets.symmetric(vertical: 8.0),
       itemCount: _currentChatMessages.length,
       itemBuilder: (context, index) {
         final message = _currentChatMessages[index];
         final messageSources = _messageSources[message.messageId] ?? const <AcademicSource>[];
         final isLatestUserMessage = message.isUser && index == lastUserIndex;
         return ChatMessageWidget(
           key: ValueKey(message.messageId),
           text: message.text,
           imageBytes: message.imageBytes,
           index: index,
           isUser: message.isUser,
           onLongPress: () {
             if (message.text != null && mounted) {
               setState(() {
                 _selectedMessageIndex = index;
                 _selectedMessageTextForCopy = message.text;
               });
               _log("Selected message $index for copy.");
             }
           },
           onTap: _clearSelection,
           isSelected: _selectedMessageIndex == index,
           isQueued: message.isQueued,
           isEdited: message.isEdited,
           webToolStatus: _webToolStatusByMessageId[message.messageId] ?? (messageSources.isNotEmpty ? 'used' : null),
             onCopyMessage: message.isUser && message.text != null ? () => _copyQuestionText(message) : null,
             onEditMessage: isLatestUserMessage && !_isLoading && !_isListening
               ? () => _startEditingLastUserMessage(message)
               : null,
             onRetryMessage: isLatestUserMessage && !message.isQueued && !_isLoading && !_isListening && !_isOffline
               ? () => _retryLastUserMessage(message)
               : null,
           sources: messageSources,
           savedSourceIds: _savedSourceIds,
           citationStyle: _citationStyle,
           onToggleSourceSaved: _toggleSavedSource,
           onFactCheck: !message.isUser && message.text != null && message.text != '...'
               ? () => _factCheckMessage(message, messageSources)
               : null,
           onBuildLiteratureReview: !message.isUser && messageSources.length > 1
               ? () => _buildLiteratureReview(messageSources)
               : null,
         );
       },
     );

     Widget chatArea = Column(
       children: [
         Expanded(
           child: GestureDetector(
             onTap: () { _clearSelection(); FocusScope.of(context).unfocus(); },
             behavior: HitTestBehavior.translucent,
             child: Container(
               decoration: const BoxDecoration(
                 gradient: LinearGradient(
                   begin: Alignment.topCenter,
                   end: Alignment.bottomCenter,
                   colors: [Color(0xFF0A0F1A), Color(0xFF080C14)],
                 ),
               ),
               child: chatList,
             ),
           ),
         ),
         _buildTextInputArea(),
       ],
     );

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(),
      drawer: isLargeScreen ? null : Drawer(child: _buildSidebarContent()),
      body: Row(
        children: [
          if (isLargeScreen) SizedBox(width: 280, child: _buildSidebarContent()),
          if (isLargeScreen) const VerticalDivider(width: 1, thickness: 1),
          Expanded( child: chatArea, ),
        ],
      ),
    );
  }

  void _scrollToBottom({int delayMillis = 50}) {
    _updateThrottleTimer?.cancel();
    _updateThrottleTimer = Timer(Duration(milliseconds: delayMillis), () {
      if (_chatScrollController.hasClients && _chatScrollController.position.hasContentDimensions) {
        _chatScrollController.animateTo( _chatScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOutQuad, );
      }
    });
  }

  Future<void> _stopGeneratingResponse() async {
    if (!_isStreamingResponse) {
      return;
    }
    _cancelStreamingResponseRequested = true;
    try {
      await _responseStreamSubscription?.cancel();
    } catch (e) {
      _log("Error cancelling response stream: $e");
    } finally {
      _responseStreamSubscription = null;
      if (!(_responseStreamDoneCompleter?.isCompleted ?? true)) {
        _responseStreamDoneCompleter?.complete();
      }
    }
    if (mounted) {
      _showSnackbar('Generation stopped.');
    }
  }

  void _showSnackbar(String message, {Duration duration = const Duration(seconds: 3), Color? bgColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(message), duration: duration, backgroundColor: bgColor, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), margin: const EdgeInsets.all(8), ), );
    _log("Snackbar shown: '$message'");
  }

  Future<void> _launchUrl(String url, BuildContext context) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      if (mounted) { _showSnackbar('Could not launch $url', bgColor: Colors.redAccent); }
      _log("Could not launch URL: $url");
    } else {
      try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
      catch (e) {
        _log("Error launching URL $url: $e");
        if (mounted) {
          _showSnackbar('Could not open the link.', bgColor: Colors.redAccent);
        }
      }
    }
  }

}
