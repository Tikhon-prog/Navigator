import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_navigation_intent.dart';
import 'ai_navigation_commands.dart';
import 'ai_schedule_commands.dart';
import 'navigation_preferences.dart';

/// On-device assistant. The GGUF model is stored outside the APK and runs locally.
class LocalAiChatPage extends StatefulWidget {
  final String? Function(
    String destinationId,
    String? startLocationId,
    Set<String> avoidLocationIds,
  )? onRouteRequest;
  final Future<String?> Function()? loadMathClassName;
  final Future<Map<int, int>?> Function()? loadMathSlotsByDay;
  final Future<void> Function(
    String className,
    Map<int, List<String>> assignments,
  )? onApplyMathSchedule;

  const LocalAiChatPage({
    super.key,
    this.onRouteRequest,
    this.loadMathClassName,
    this.loadMathSlotsByDay,
    this.onApplyMathSchedule,
  });

  @override
  State<LocalAiChatPage> createState() => _LocalAiChatPageState();
}

class _ChatLine {
  final bool fromUser;
  String text;
  _ChatLine(this.fromUser, this.text);
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest digest) => value = digest;

  @override
  void close() {}
}

enum _LocalModelPreset { compact, russian }

extension on _LocalModelPreset {
  String get fileName => this == _LocalModelPreset.compact
      ? 'smollm2-135m-instruct-q4_k_m.gguf'
      : 'qwen2.5-0.5b-instruct-q4_k_m.gguf';

  String get url => this == _LocalModelPreset.compact
      ? 'https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf'
      : 'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf';

  String get label => this == _LocalModelPreset.compact
      ? 'SmolLM2 135M · около 105 МБ'
      : 'Qwen2.5 0.5B · около 398 МБ';

  String get description => this == _LocalModelPreset.compact
      ? 'Самый компактный вариант (~105 МБ). Он в основном ориентирован на английский; русский диалог будет заметно слабее.'
      : 'Основная модель (~398 МБ), лучше подходит для русского. Скачивается отдельно от приложения и после загрузки работает офлайн.';
}

class _LocalAiChatPageState extends State<LocalAiChatPage> {
  _LocalModelPreset _selectedPreset = _LocalModelPreset.russian;
  static const _expectedQwenSha256 =
      '6eb923e7d26e9cea28811e1a8e852009b21242fb157b26149d3b188f3a8c8653';

  static const _systemPrompt = '''
Ты локальный ИИ-помощник школы «Поколение». Отвечай по-русски, кратко и дружелюбно.
Ты работаешь на устройстве без облака. Не выдумывай расписание, кабинеты, этажи,
лестницы, маршруты, уроки и школьные правила. Используй только переданные приложением
данные. Ты можешь предложить изменения, но не утверждай, что уже сохранил их:
приложение отдельно проверяет команды и просит подтверждение перед изменением расписания.
Не изменяй схему коридоров по одному сообщению пользователя. Не утверждай, что
подключён к интернету или школьной базе.
''';

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatLine> _lines = [
    _ChatLine(false,
        'Привет! Я локальный ИИ-помощник. Поиск кабинетов и построение маршрутов доступны без скачивания модели. Для свободного диалога можно установить компактную модель (~105 МБ); для более качественных ответов по-русски доступен Qwen (~355 МБ). После загрузки выбранная модель работает без интернета.')
  ];
  final List<LLMMessage> _history = [
    LLMMessage(role: LLMRole.system, content: _systemPrompt),
  ];

  LlamaCppChatRepository? _chatRepository;
  String? _modelPath;
  bool _busy = false;
  bool _downloading = false;
  bool _loadingModel = false;
  double? _downloadProgress;
  String? _statusError;
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _places = [];
  AiMathScheduleDraft? _pendingMathDraft;
  String? _pendingMathClass;
  bool _awaitingMathConfirmation = false;
  String? _lastRouteDestination;
  String? _lastRouteStart;
  late final Future<void> _catalogLoadFuture;

  @override
  void initState() {
    super.initState();
    _catalogLoadFuture = _loadSchoolCatalog();
    _findExistingModel();
  }

  Future<void> _loadSchoolCatalog() async {
    try {
      final rooms = jsonDecode(await rootBundle.loadString('assets/data/rooms.json'));
      if (rooms is Map && rooms['rooms'] is List) {
        _rooms = (rooms['rooms'] as List).whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    try {
      final places = jsonDecode(await rootBundle.loadString('assets/data/places.json'));
      if (places is Map && places['places'] is List) {
        _places = (places['places'] as List).whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
  }

  Future<File> _modelFile([_LocalModelPreset? preset]) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/local_ai_models');
    await directory.create(recursive: true);
    return File('${directory.path}/${(preset ?? _selectedPreset).fileName}');
  }

  Future<void> _findExistingModel() async {
    try {
      final preferredPresets = [
        _selectedPreset,
        ..._LocalModelPreset.values.where((preset) => preset != _selectedPreset),
      ];
      for (final preset in preferredPresets) {
        final file = await _modelFile(preset);
        if (await _isModelReady(file, preset)) {
          if (mounted) setState(() {
            _selectedPreset = preset;
            _modelPath = file.path;
          });
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _selectModelPreset(_LocalModelPreset preset) async {
    if (_busy || _downloading || _loadingModel) return;
    final file = await _modelFile(preset);
    if (_selectedPreset == preset && _modelPath == file.path) return;
    _chatRepository?.dispose();
    _chatRepository = null;
    final ready = await _isModelReady(file, preset);
    if (!mounted) return;
    setState(() {
      _selectedPreset = preset;
      _modelPath = ready ? file.path : null;
      _statusError = null;
      _downloadProgress = null;
    });
  }

  String get _activeModelLabel {
    if (_modelPath?.endsWith('qwen2.5-0.5b-instruct-q4_k_m.gguf') ?? false) {
      return 'Qwen2.5 0.5B · Q4_K_M';
    }
    return _selectedPreset.label;
  }

  Future<bool> _isModelReady(File file, _LocalModelPreset preset) async {
    try {
      final minimumBytes = (preset == _LocalModelPreset.compact ? 95 : 370) *
          1024 * 1024;
      if (!await file.exists() || await file.length() < minimumBytes) {
        return false;
      }
      final marker = File('${file.path}.sha256');
      if (!await marker.exists()) return false;
      final savedDigest = (await marker.readAsString()).trim().toLowerCase();
      if (savedDigest.length != 64) return false;
      if (preset == _LocalModelPreset.russian &&
          savedDigest != _expectedQwenSha256) {
        return false;
      }
      return await _hasGgufHeader(file);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasGgufHeader(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      final header = await handle.read(4);
      return String.fromCharCodes(header) == 'GGUF';
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  Future<void> _downloadModel() async {
    if (_downloading || _busy) return;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _statusError = null;
    });
    File? finalFile;
    File? partialFile;
    IOSink? sink;
    try {
      finalFile = await _modelFile();
      partialFile = File('${finalFile.path}.part');
      if (await partialFile.exists()) await partialFile.delete();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      try {
        final request = await client.getUrl(Uri.parse(_selectedPreset.url));
        request.followRedirects = true;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Сервер модели вернул HTTP ${response.statusCode}.');
        }
        final total = response.contentLength;
        final digestOutput = _DigestSink();
        final digestInput = sha256.startChunkedConversion(digestOutput);
        sink = partialFile.openWrite();
        var received = 0;
        await for (final chunk in response) {
          sink.add(chunk);
          digestInput.add(chunk);
          received += chunk.length;
          if (mounted && total > 0) {
            setState(() => _downloadProgress =
                (received / total).clamp(0.0, 1.0).toDouble());
          }
        }
        digestInput.close();
        await sink.flush();
        await sink.close();
        sink = null;

        final minimumBytes =
            (_selectedPreset == _LocalModelPreset.compact ? 95 : 370) *
                1024 * 1024;
        if (await partialFile.length() < minimumBytes) {
          throw const FormatException(
            'Скачанный файл слишком мал и похож на страницу ошибки вместо GGUF-модели.',
          );
        }
        if (!await _hasGgufHeader(partialFile)) {
          throw const FormatException('Файл не является GGUF-моделью.');
        }
        final actualDigest = digestOutput.value?.toString();
        if (actualDigest == null) throw const FormatException('Не удалось проверить SHA-256 модели.');
        if (_selectedPreset == _LocalModelPreset.russian &&
            actualDigest != _expectedQwenSha256) {
          throw const FormatException(
            'SHA-256 модели не совпадает. Файл удалён, чтобы не запускать повреждённую модель.',
          );
        }
        if (total > 0 && received != total) {
          throw const FormatException(
            'Загрузка завершилась раньше ожидаемого размера файла.',
          );
        }

        if (await finalFile.exists()) await finalFile.delete();
        await partialFile.rename(finalFile.path);
        await File('${finalFile.path}.sha256')
            .writeAsString(actualDigest, flush: true);

        if (mounted) {
          setState(() {
            _modelPath = finalFile!.path;
            _downloadProgress = 1;
          });
        }
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      try { await sink?.close(); } catch (_) {}
      try {
        if (partialFile != null && await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _statusError = 'Не удалось скачать модель: $error');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _ensureLoaded() async {
    if (_chatRepository != null) return;
    if (_modelPath == null) {
      throw StateError('Сначала скачай модель. Это делается один раз.');
    }
    if (mounted) setState(() => _loadingModel = true);
    try {
      final chat = LlamaCppChatRepository(
        contextSize: 1536,
        batchSize: 128,
        threads: 2,
        nGpuLayers: 0,
      );
      try {
        await chat.loadModel(_modelPath!);
        _chatRepository = chat;
      } catch (_) {
        chat.dispose();
        rethrow;
      }
    } finally {
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  Future<AiNavigationIntent?> _resolveNavigationWithLocalModel(String query) async {
    if (_modelPath == null) return null;
    await _ensureLoaded();
    final knownRows = <Map<String, dynamic>>[
      ..._rooms,
      ..._places,
    ].map((row) => <String, dynamic>{
      'id': '${row['id'] ?? row['number'] ?? ''}'.trim(),
      'name': '${row['name'] ?? ''}'.trim(),
      if (row['floor'] != null) 'floor': row['floor'],
    }).where((row) => (row['id'] as String).isNotEmpty).toList();
    final prompt = '''
Выбери пункт назначения из каталога школьной карты для запроса пользователя.
Каталог ниже — единственный источник допустимых ID. Не выдумывай ID.
Если указан только пункт назначения, startLocationId должен быть null.
Ответь только JSON:
{"destinationId":"ID из каталога","startLocationId":null}
или {"destinationId":"ID назначения","startLocationId":"ID начала"}.
Если не уверен, ответь {"destinationId":null,"startLocationId":null}.
КАТАЛОГ: ${jsonEncode(knownRows)}
ЗАПРОС: $query
''';
    final response = await _chatRepository!.chatResponse(
      'model',
      messages: [
        LLMMessage(
          role: LLMRole.system,
          content: 'Ты классификатор навигационных запросов. Выдавай только JSON; не выдумывай пункты карты.',
        ),
        LLMMessage(role: LLMRole.user, content: prompt),
      ],
    );
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(response.content);
    if (match == null) return null;
    try {
      return AiNavigationIntent.fromModelCandidate(
        jsonDecode(match.group(0)!),
        knownRoomIds: knownRows.map((row) => row['id'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  String? _offlineRoomAnswer(String text) {
    final query = text.toLowerCase();
    final match = RegExp(r'(?<!\d)(\d{3}(?:\.\d+)?)(?!\d)').firstMatch(query);
    final asksAboutRoom = <String>['кабинет', 'комнат', 'этаж', 'где', 'найди', 'номер', 'маршрут', 'как пройти', 'как дойти'].any(query.contains);
    if (asksAboutRoom && match != null) {
      final wanted = match.group(1)!.trim();
      final all = [..._rooms, ..._places];
      final hits = all.where((row) =>
          '${row['id'] ?? row['number'] ?? ''}'.trim().toLowerCase() == wanted ||
          '${row['name'] ?? ''}'.trim().toLowerCase() == wanted).toList();
      if (hits.isNotEmpty) {
        final item = hits.first;
        final name = '${item['name'] ?? 'Кабинет $wanted'}';
        final floor = item['floor'];
        final floorText = floor == null ? '' : ' Этаж: $floor.';
        return 'По встроенным данным карты найдено: $name (№$wanted).$floorText\n\nЯ не буду придумывать путь по этажу. Открой раздел «Карта школы», выбери этот кабинет и проверь построенный маршрут.';
      }
      return 'В офлайн-каталоге не найден кабинет №$wanted. Возможно, карта устарела или номер записан иначе. Проверь номер на схеме; я не буду угадывать этаж.';
    }
    if (query.contains('маршрут') || query.contains('как пройти') || query.contains('как дойти')) {
      return 'Маршруты строятся по встроенной схеме коридоров и переходов между этажами. Чтобы не подсказать неверный путь, открой «Карта школы» и выбери точку назначения. Свободный чат не заменяет проверенный алгоритм маршрутизации.';
    }
    if (query.contains('интернет') || query.contains('офлайн') || query.contains('без сети')) {
      return 'Карта, поиск кабинетов и локальные функции работают без интернета. После загрузки модели свободный ИИ-чат тоже работает на устройстве и не отправляет сообщения в облако.';
    }
    return null;
  }

  void _appendAssistant(String message) {
    if (!mounted) return;
    setState(() => _lines.add(_ChatLine(false, message)));
    _scrollToBottom();
  }

  String _mathClarification(AiMathScheduleDraft draft) {
    final slot = draft.missingSlots.first;
    const days = {
      1: 'понедельник',
      2: 'вторник',
      3: 'среду',
      4: 'четверг',
      5: 'пятницу',
      6: 'субботу',
    };
    return 'На ${days[slot.day] ?? 'день ${slot.day}'} '
        '${draft.assignments[slot.day]!.length}-й математический урок ещё не указан. '
        'Что поставить ${slot.slot + 1}-м уроком: геометрию, алгебру или вероятность и статистику?';
  }

  Future<void> _handlePendingMathMessage(String text) async {
    final draft = _pendingMathDraft!;
    final normalizedInput = text.toLowerCase().trim();
    if (RegExp(r'^(отмена|нет|не надо|не сохраняй|cancel)[.! ]*$')
        .hasMatch(normalizedInput)) {
      _pendingMathDraft = null;
      _pendingMathClass = null;
      _awaitingMathConfirmation = false;
      _appendAssistant('Изменения отменены. Текущее расписание не менялось.');
      return;
    }
    if (_awaitingMathConfirmation) {
      final normalized = text.toLowerCase().trim();
      if (RegExp(r'^(да|подтверждаю|подтвердить|сохрани|применить|ок|yes)[.! ]*
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _busy = true;
      _statusError = null;
      _lines.add(_ChatLine(true, text));
    });
    _scrollToBottom();

    await _catalogLoadFuture;
    if (_pendingMathDraft != null) {
      await _handlePendingMathMessage(text);
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (await _handleMathScheduleCommand(text)) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final knownRoomIds = [
      ..._rooms.map((row) => '${row['id'] ?? row['number'] ?? ''}'),
      ..._places.map((row) => '${row['id'] ?? row['number'] ?? ''}'),
    ];
    if (await _handleNavigationPreferences(text, knownRoomIds)) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    var intent = AiNavigationIntent.parse(text, knownRoomIds: knownRoomIds);
    if (intent == null &&
        AiNavigationIntent.looksLikeRouteRequest(text) &&
        _modelPath != null) {
      try {
        intent = await _resolveNavigationWithLocalModel(text);
      } catch (_) {
        // The verified graph still validates every route.
      }
    }
    if (intent != null && widget.onRouteRequest != null) {
      _lastRouteDestination = intent.destinationId;
      _lastRouteStart = intent.startLocationId;
      final avoided = await NavigationPreferences.loadAvoidedLocations();
      final reply = widget.onRouteRequest!(
        intent.destinationId,
        intent.startLocationId,
        avoided,
      );
      if (reply != null) {
        setState(() {
          _lines.add(_ChatLine(false, reply));
          _busy = false;
        });
        _scrollToBottom();
        return;
      }
    }
    final offlineAnswer = _offlineRoomAnswer(text);
    if (offlineAnswer != null) {
      setState(() {
        _lines.add(_ChatLine(false, offlineAnswer));
        _busy = false;
      });
      _scrollToBottom();
      return;
    }

    if (_modelPath == null) {
      setState(() {
        _lines.add(_ChatLine(false,
            'Свободный диалог пока недоступен: локальная модель ещё не скачана. Нажми «Скачать модель» выше. Поиск кабинетов и подсказки по навигации доступны уже сейчас без модели и интернета.'));
        _busy = false;
      });
      _scrollToBottom();
      return;
    }

    final answerLine = _ChatLine(false, '');
    setState(() => _lines.add(answerLine));
    try {
      await _ensureLoaded();
      _history.add(LLMMessage(role: LLMRole.user, content: text));
      final repo = _chatRepository!;
      await for (final chunk in repo.streamChat('model', messages: _history)) {
        final part = chunk.message?.content ?? '';
        if (part.isNotEmpty && mounted) {
          answerLine.text += part;
          setState(() {});
          _scrollToBottom();
        }
      }
      if (answerLine.text.trim().isEmpty) {
        answerLine.text = 'Модель не вернула ответ. Попробуй сформулировать вопрос короче.';
      }
      _history.add(LLMMessage(role: LLMRole.assistant, content: answerLine.text));
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusError = 'Локальная модель не запустилась: $error';
          answerLine.text = 'Не удалось запустить модель на этом устройстве. Поиск кабинетов офлайн остаётся доступен.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _chatRepository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Локальный ИИ-помощник'),
        actions: [
          IconButton(
            tooltip: 'Очистить чат',
            onPressed: _busy ? null : () => setState(() {
              _lines
                ..clear()
                ..add(_ChatLine(false, 'Чат очищен. Я работаю локально на этом устройстве.'));
              _history
                ..clear()
                ..add(LLMMessage(role: LLMRole.system, content: _systemPrompt));
            }),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_modelPath == null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Скачай локальную нейросеть',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<_LocalModelPreset>(
                      value: _selectedPreset,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Модель'),
                      items: _LocalModelPreset.values.map((preset) => DropdownMenuItem(
                        value: preset,
                        child: Text(preset.label, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: _downloading || _busy ? null : (preset) {
                        if (preset != null) _selectModelPreset(preset);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(_selectedPreset.description),
                    const SizedBox(height: 5),
                    const Text('Модель хранится отдельно от APK. Перед запуском проверяется формат GGUF и SHA-256 основной модели. После загрузки чат работает офлайн; карта и расписание доступны и без модели.'),
                    const SizedBox(height: 10),
                    if (_downloading) ...[
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 5),
                      Text(_downloadProgress == null
                          ? 'Загрузка модели…'
                          : 'Загружено ${(_downloadProgress! * 100).round()}%'),
                    ] else
                      FilledButton.icon(
                        onPressed: _downloadModel,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Скачать модель'),
                      ),
                    if (_statusError != null) ...[
                      const SizedBox(height: 8),
                      Text(_statusError!, style: TextStyle(color: colors.error)),
                    ],
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.offline_bolt_rounded),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Модель сохранена на устройстве', style: TextStyle(fontWeight: FontWeight.w800)),
                          Text('Интернет не нужен · ${_activeModelLabel}', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (_loadingModel)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    PopupMenuButton<_LocalModelPreset>(
                      tooltip: 'Сменить модель',
                      enabled: !_busy && !_downloading && !_loadingModel,
                      onSelected: _selectModelPreset,
                      itemBuilder: (_) => _LocalModelPreset.values.map((preset) => PopupMenuItem(
                        value: preset,
                        child: Text(preset.label),
                      )).toList(),
                      icon: const Icon(Icons.swap_horiz_rounded),
                    ),
                  ],
                ),
              ),
            if (_statusError != null && _modelPath != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Text(_statusError!, style: TextStyle(color: colors.error)),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                itemCount: _lines.length,
                itemBuilder: (context, index) {
                  final line = _lines[index];
                  return Align(
                    alignment: line.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .86),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: line.fromUser ? colors.primaryContainer : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: SelectableText(line.text.isEmpty && _busy ? 'Думаю…' : line.text),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Спроси что-нибудь…',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    tooltip: 'Отправить',
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
)
          .hasMatch(normalized)) {
        final className = _pendingMathClass;
        final save = widget.onApplyMathSchedule;
        if (className == null || save == null) {
          _pendingMathDraft = null;
          _awaitingMathConfirmation = false;
          _appendAssistant('Не удалось сохранить расписание: функция записи недоступна.');
          return;
        }
        try {
          await save(className, draft.completedAssignments);
          _pendingMathDraft = null;
          _pendingMathClass = null;
          _awaitingMathConfirmation = false;
          _appendAssistant('Готово. Персональные названия математических уроков сохранены. '
              'Остальные предметы и расписание класса не изменялись.');
        } catch (error) {
          _appendAssistant('Не удалось сохранить изменения: $error');
        }
        return;
      }
      if (RegExp(r'^(нет|отмена|не надо|не сохраняй|cancel)[.! ]*
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _busy = true;
      _statusError = null;
      _lines.add(_ChatLine(true, text));
    });
    _scrollToBottom();

    await _catalogLoadFuture;
    final knownRoomIds = [
      ..._rooms.map((row) => '${row['id'] ?? row['number'] ?? ''}'),
      ..._places.map((row) => '${row['id'] ?? row['number'] ?? ''}'),
    ];
    var intent = AiNavigationIntent.parse(text, knownRoomIds: knownRoomIds);
    if (intent == null &&
        AiNavigationIntent.looksLikeRouteRequest(text) &&
        _modelPath != null) {
      try {
        intent = await _resolveNavigationWithLocalModel(text);
      } catch (_) {
        // Optional neural intent resolution may fail; graph navigation still works.
      }
    }
    if (intent != null && widget.onRouteRequest != null) {
      final reply = widget.onRouteRequest!(intent.destinationId, intent.startLocationId);
      if (reply != null) {
        setState(() {
          _lines.add(_ChatLine(false, reply));
          _busy = false;
        });
        _scrollToBottom();
        return;
      }
    }
    final offlineAnswer = _offlineRoomAnswer(text);
    if (offlineAnswer != null) {
      setState(() {
        _lines.add(_ChatLine(false, offlineAnswer));
        _busy = false;
      });
      _scrollToBottom();
      return;
    }

    if (_modelPath == null) {
      setState(() {
        _lines.add(_ChatLine(false,
            'Свободный диалог пока недоступен: локальная модель ещё не скачана. Нажми «Скачать модель» ниже. Поиск кабинетов и подсказки по навигации доступны уже сейчас без модели и интернета.'));
        _busy = false;
      });
      _scrollToBottom();
      return;
    }

    final answerLine = _ChatLine(false, '');
    setState(() => _lines.add(answerLine));
    try {
      await _ensureLoaded();
      _history.add(LLMMessage(role: LLMRole.user, content: text));
      final repo = _chatRepository!;
      await for (final chunk in repo.streamChat('model', messages: _history)) {
        final part = chunk.message?.content ?? '';
        if (part.isNotEmpty && mounted) {
          answerLine.text += part;
          setState(() {});
          _scrollToBottom();
        }
      }
      if (answerLine.text.trim().isEmpty) {
        answerLine.text = 'Модель не вернула ответ. Попробуй сформулировать вопрос короче.';
      }
      _history.add(LLMMessage(role: LLMRole.assistant, content: answerLine.text));
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusError = 'Локальная модель не запустилась: $error';
          answerLine.text = 'Не удалось запустить модель на этом устройстве. Поиск кабинетов офлайн остаётся доступен.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _chatRepository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Локальный ИИ-помощник'),
        actions: [
          IconButton(
            tooltip: 'Очистить чат',
            onPressed: _busy ? null : () => setState(() {
              _lines
                ..clear()
                ..add(_ChatLine(false, 'Чат очищен. Я работаю локально на этом устройстве.'));
              _history
                ..clear()
                ..add(LLMMessage(role: LLMRole.system, content: _systemPrompt));
            }),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_modelPath == null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Скачай локальную нейросеть',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<_LocalModelPreset>(
                      value: _selectedPreset,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Модель'),
                      items: _LocalModelPreset.values.map((preset) => DropdownMenuItem(
                        value: preset,
                        child: Text(preset.label, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: _downloading || _busy ? null : (preset) {
                        if (preset != null) _selectModelPreset(preset);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(_selectedPreset.description),
                    const SizedBox(height: 5),
                    const Text('Модель хранится отдельно от APK. Перед запуском проверяется формат GGUF и SHA-256 основной модели. После загрузки чат работает офлайн; карта и расписание доступны и без модели.'),
                    const SizedBox(height: 10),
                    if (_downloading) ...[
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 5),
                      Text(_downloadProgress == null
                          ? 'Загрузка модели…'
                          : 'Загружено ${(_downloadProgress! * 100).round()}%'),
                    ] else
                      FilledButton.icon(
                        onPressed: _downloadModel,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Скачать модель'),
                      ),
                    if (_statusError != null) ...[
                      const SizedBox(height: 8),
                      Text(_statusError!, style: TextStyle(color: colors.error)),
                    ],
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.offline_bolt_rounded),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Модель сохранена на устройстве', style: TextStyle(fontWeight: FontWeight.w800)),
                          Text('Интернет не нужен · ${_activeModelLabel}', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (_loadingModel)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    PopupMenuButton<_LocalModelPreset>(
                      tooltip: 'Сменить модель',
                      enabled: !_busy && !_downloading && !_loadingModel,
                      onSelected: _selectModelPreset,
                      itemBuilder: (_) => _LocalModelPreset.values.map((preset) => PopupMenuItem(
                        value: preset,
                        child: Text(preset.label),
                      )).toList(),
                      icon: const Icon(Icons.swap_horiz_rounded),
                    ),
                  ],
                ),
              ),
            if (_statusError != null && _modelPath != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Text(_statusError!, style: TextStyle(color: colors.error)),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                itemCount: _lines.length,
                itemBuilder: (context, index) {
                  final line = _lines[index];
                  return Align(
                    alignment: line.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .86),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: line.fromUser ? colors.primaryContainer : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: SelectableText(line.text.isEmpty && _busy ? 'Думаю…' : line.text),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Спроси что-нибудь…',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    tooltip: 'Отправить',
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
)
          .hasMatch(normalized)) {
        _pendingMathDraft = null;
        _pendingMathClass = null;
        _awaitingMathConfirmation = false;
        _appendAssistant('Изменения отменены. Текущее расписание не менялось.');
        return;
      }
      _appendAssistant('Я подготовил изменения, но ещё не сохранил их. '
          'Напиши «подтверждаю» или «отмена».');
      return;
    }

    final subject = draft.fillNext(text);
    if (subject == null) {
      _appendAssistant('Не распознал предмет. Напиши «геометрия», «алгебра» '
          'или «ВиС» (вероятность и статистика).');
      return;
    }
    if (draft.missingSlots.isNotEmpty) {
      _appendAssistant('Записал: $subject. ${_mathClarification(draft)}');
      return;
    }
    _awaitingMathConfirmation = true;
    _appendAssistant('Проверь предварительный вариант:\n${draft.preview()}\n\n'
        'Пока ничего не сохранено. Напиши «подтверждаю», чтобы применить, '
        'или «отмена», чтобы оставить прежнее расписание.');
  }

  Future<bool> _handleMathScheduleCommand(String text) async {
    if (widget.loadMathSlotsByDay == null ||
        widget.loadMathClassName == null ||
        widget.onApplyMathSchedule == null) {
      return false;
    }
    final hasDay = RegExp(
      r'(?<![А-Яа-яЁё])(понедельника?|пн|вторника?|вт|сред[ауые]?|ср|четверга?|чт|пятниц[ауые]?|пт|суббот[ауые]?|сб)(?![А-Яа-яЁё])',
      caseSensitive: false,
    ).hasMatch(text);
    if (!hasDay) return false;

    final className = await widget.loadMathClassName!.call();
    final slots = await widget.loadMathSlotsByDay!.call();
    if (className == null || className.trim().isEmpty || slots == null) {
      _appendAssistant('Сначала выбери свой класс в разделе «Учёба → Расписание». '
          'Я не могу менять предметы без данных твоего класса.');
      return true;
    }
    final draft = AiMathScheduleParser.parse(text, mathSlotsByDay: slots);
    if (draft == null) return false;
    if (draft.errors.isNotEmpty) {
      _appendAssistant(draft.errors.join('\n'));
      return true;
    }
    if (draft.assignments.isEmpty) {
      _appendAssistant('Не нашёл математических уроков для изменения.');
      return true;
    }
    _pendingMathDraft = draft;
    _pendingMathClass = className;
    if (draft.missingSlots.isNotEmpty) {
      _appendAssistant(_mathClarification(draft));
    } else {
      _awaitingMathConfirmation = true;
      _appendAssistant('Предлагаю изменить только математические предметы:\n'
          '${draft.preview()}\n\n'
          'Пока ничего не сохранено. Напиши «подтверждаю», чтобы применить, '
          'или «отмена», чтобы оставить прежнее расписание.');
    }
    return true;
  }

  Future<bool> _handleNavigationPreferences(
    String text,
    List<String> knownLocationIds,
  ) async {
    final commands = AiNavigationCommandParser.parse(
      text,
      knownLocationIds: knownLocationIds,
    );
    if (commands.isEmpty) return false;

    final messages = <String>[];
    for (final command in commands) {
      final room = [..._rooms, ..._places].where((row) =>
          '${row['id'] ?? row['number'] ?? ''}'.trim() == command.locationId);
      final name = room.isEmpty ? 'кабинет ${command.locationId}' :
          '${room.first['name'] ?? 'кабинет ${command.locationId}'} №${command.locationId}';
      switch (command.type) {
        case AiNavigationCommandType.avoidLocation:
          await NavigationPreferences.avoid(command.locationId);
          messages.add('Запомнил: буду стараться прокладывать путь в обход $name.');
          break;
        case AiNavigationCommandType.allowLocation:
          await NavigationPreferences.allow(command.locationId);
          messages.add('Ограничение для $name снято.');
          break;
        case AiNavigationCommandType.routeFeedback:
          await NavigationPreferences.saveFeedback(
            locationId: command.locationId,
            message: command.text,
          );
          messages.add('Сохранил замечание о маршруте около $name. '
              'Саму схему коридоров я не меняю автоматически: её нужно сверить '
              'с планом школы, иначе можно создать опасный путь.');
          break;
      }
    }

    if (_lastRouteDestination == null) {
      final storedRoute = await NavigationPreferences.loadLastRoute();
      _lastRouteDestination = storedRoute['destination_id'];
      _lastRouteStart = storedRoute['start_location_id'];
    }
    final avoided = await NavigationPreferences.loadAvoidedLocations();
    final hasAvoid = commands.any((command) =>
        command.type == AiNavigationCommandType.avoidLocation ||
        command.type == AiNavigationCommandType.allowLocation);
    final hasFeedback = commands.any((command) =>
        command.type == AiNavigationCommandType.routeFeedback);
    final shouldRecheck = hasAvoid || hasFeedback;
    if (shouldRecheck &&
        _lastRouteDestination != null &&
        widget.onRouteRequest != null) {
      final routeReply = widget.onRouteRequest!(
        _lastRouteDestination!,
        _lastRouteStart,
        avoided,
      );
      if (routeReply != null) {
        messages.add(hasFeedback
            ? 'Перепроверил маршрут по актуальному графу коридоров. $routeReply'
            : routeReply);
      }
    } else if (hasAvoid) {
      messages.add('Предпочтение сохранено для следующих маршрутов.');
    } else if (hasFeedback) {
      messages.add('Замечание сохранено. Построй этот маршрут ещё раз, чтобы я мог перепроверить его.');
    }
    _appendAssistant(messages.join('\n\n'));
    return true;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _busy = true;
      _statusError = null;
      _lines.add(_ChatLine(true, text));
    });
    _scrollToBottom();

    await _catalogLoadFuture;
    if (_pendingMathDraft != null) {
      await _handlePendingMathMessage(text);
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (await _handleMathScheduleCommand(text)) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final knownRoomIds = [
      ..._rooms.map((row) => '${row['id'] ?? row['number'] ?? ''}'),
      ..._places.map((row) => '${row['id'] ?? row['number'] ?? ''}'),
    ];
    if (await _handleNavigationPreferences(text, knownRoomIds)) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    var intent = AiNavigationIntent.parse(text, knownRoomIds: knownRoomIds);
    if (intent == null &&
        AiNavigationIntent.looksLikeRouteRequest(text) &&
        _modelPath != null) {
      try {
        intent = await _resolveNavigationWithLocalModel(text);
      } catch (_) {
        // The verified route graph remains the final authority.
      }
    }
    if (intent != null && widget.onRouteRequest != null) {
      _lastRouteDestination = intent.destinationId;
      _lastRouteStart = intent.startLocationId;
      final avoided = await NavigationPreferences.loadAvoidedLocations();
      final reply = widget.onRouteRequest!(
        intent.destinationId,
        intent.startLocationId,
        avoided,
      );
      if (reply != null) {
        setState(() {
          _lines.add(_ChatLine(false, reply));
          _busy = false;
        });
        _scrollToBottom();
        return;
      }
    }
    final offlineAnswer = _offlineRoomAnswer(text);
    if (offlineAnswer != null) {
      setState(() {
        _lines.add(_ChatLine(false, offlineAnswer));
        _busy = false;
      });
      _scrollToBottom();
      return;
    }

    if (_modelPath == null) {
      setState(() {
        _lines.add(_ChatLine(false,
            'Свободный диалог пока недоступен: локальная модель ещё не скачана. Нажми «Скачать модель» ниже. Поиск кабинетов и подсказки по навигации доступны уже сейчас без модели и интернета.'));
        _busy = false;
      });
      _scrollToBottom();
      return;
    }

    final answerLine = _ChatLine(false, '');
    setState(() => _lines.add(answerLine));
    try {
      await _ensureLoaded();
      _history.add(LLMMessage(role: LLMRole.user, content: text));
      final repo = _chatRepository!;
      await for (final chunk in repo.streamChat('model', messages: _history)) {
        final part = chunk.message?.content ?? '';
        if (part.isNotEmpty && mounted) {
          answerLine.text += part;
          setState(() {});
          _scrollToBottom();
        }
      }
      if (answerLine.text.trim().isEmpty) {
        answerLine.text = 'Модель не вернула ответ. Попробуй сформулировать вопрос короче.';
      }
      _history.add(LLMMessage(role: LLMRole.assistant, content: answerLine.text));
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusError = 'Локальная модель не запустилась: $error';
          answerLine.text = 'Не удалось запустить модель на этом устройстве. Поиск кабинетов офлайн остаётся доступен.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _chatRepository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Локальный ИИ-помощник'),
        actions: [
          IconButton(
            tooltip: 'Очистить чат',
            onPressed: _busy ? null : () => setState(() {
              _lines
                ..clear()
                ..add(_ChatLine(false, 'Чат очищен. Я работаю локально на этом устройстве.'));
              _history
                ..clear()
                ..add(LLMMessage(role: LLMRole.system, content: _systemPrompt));
            }),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_modelPath == null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Скачай локальную нейросеть',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<_LocalModelPreset>(
                      value: _selectedPreset,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Модель'),
                      items: _LocalModelPreset.values.map((preset) => DropdownMenuItem(
                        value: preset,
                        child: Text(preset.label, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: _downloading || _busy ? null : (preset) {
                        if (preset != null) _selectModelPreset(preset);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(_selectedPreset.description),
                    const SizedBox(height: 5),
                    const Text('Модель хранится отдельно от APK. Перед запуском проверяется формат GGUF и SHA-256 основной модели. После загрузки чат работает офлайн; карта и расписание доступны и без модели.'),
                    const SizedBox(height: 10),
                    if (_downloading) ...[
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 5),
                      Text(_downloadProgress == null
                          ? 'Загрузка модели…'
                          : 'Загружено ${(_downloadProgress! * 100).round()}%'),
                    ] else
                      FilledButton.icon(
                        onPressed: _downloadModel,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Скачать модель'),
                      ),
                    if (_statusError != null) ...[
                      const SizedBox(height: 8),
                      Text(_statusError!, style: TextStyle(color: colors.error)),
                    ],
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.offline_bolt_rounded),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Модель сохранена на устройстве', style: TextStyle(fontWeight: FontWeight.w800)),
                          Text('Интернет не нужен · ${_activeModelLabel}', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (_loadingModel)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    PopupMenuButton<_LocalModelPreset>(
                      tooltip: 'Сменить модель',
                      enabled: !_busy && !_downloading && !_loadingModel,
                      onSelected: _selectModelPreset,
                      itemBuilder: (_) => _LocalModelPreset.values.map((preset) => PopupMenuItem(
                        value: preset,
                        child: Text(preset.label),
                      )).toList(),
                      icon: const Icon(Icons.swap_horiz_rounded),
                    ),
                  ],
                ),
              ),
            if (_statusError != null && _modelPath != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Text(_statusError!, style: TextStyle(color: colors.error)),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                itemCount: _lines.length,
                itemBuilder: (context, index) {
                  final line = _lines[index];
                  return Align(
                    alignment: line.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .86),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: line.fromUser ? colors.primaryContainer : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: SelectableText(line.text.isEmpty && _busy ? 'Думаю…' : line.text),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Спроси что-нибудь…',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    tooltip: 'Отправить',
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
