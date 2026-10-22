import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_navigation_intent.dart';

/// On-device assistant. The GGUF model is stored outside the APK and runs locally.
class LocalAiChatPage extends StatefulWidget {
  final String? Function(String destinationId, String? startLocationId)? onRouteRequest;
  const LocalAiChatPage({super.key, this.onRouteRequest});

  @override
  State<LocalAiChatPage> createState() => _LocalAiChatPageState();
}

class _ChatLine {
  final bool fromUser;
  String text;
  _ChatLine(this.fromUser, this.text);
}

enum _LocalModelPreset { compact, russian }

extension on _LocalModelPreset {
  String get fileName => this == _LocalModelPreset.compact
      ? 'smollm2-135m-instruct-q4_k_m.gguf'
      : 'qwen2.5-0.5b-instruct-q3_k_m.gguf';

  String get url => this == _LocalModelPreset.compact
      ? 'https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf'
      : 'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/9a019c5233eea20db2c2cd48f9680fb0408e962d/Qwen2.5-0.5B-Instruct-Q3_K_M.gguf';

  String get label => this == _LocalModelPreset.compact
      ? 'SmolLM2 135M · около 105 МБ'
      : 'Qwen2.5 0.5B · около 355 МБ';

  String get description => this == _LocalModelPreset.compact
      ? 'Самый компактный вариант (~105 МБ). Он в основном ориентирован на английский; русский диалог будет заметно слабее.'
      : 'Основной компромисс (~355 МБ): лучше подходит для русского, чем микро-модель. Более сильное сжатие уменьшает качество относительно Q4_K_M.';
}

class _LocalAiChatPageState extends State<LocalAiChatPage> {
  _LocalModelPreset _selectedPreset = _LocalModelPreset.russian;
  static const _systemPrompt = '''
Ты локальный ИИ-помощник школы «Поколение». Отвечай по-русски, кратко и дружелюбно.
Ты работаешь на устройстве без облака. Не выдумывай расписание, адреса кабинетов,
этажи, лестницы или маршруты. Для навигации используй только сведения, которые
приложение явно передало в сообщении. Если данных не хватает, честно скажи об этом.
Не утверждай, что ты подключён к интернету или школьной базе.
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
      for (final preset in _LocalModelPreset.values) {
        final file = await _modelFile(preset);
        final minimum = preset == _LocalModelPreset.compact ? 95 : 320;
        if (await file.exists() && await file.length() > minimum * 1024 * 1024) {
          if (mounted) setState(() {
            _selectedPreset = preset;
            _modelPath = file.path;
          });
          return;
        }
      }
      // Migration: recognize the Q4_K_M model downloaded by the previous
      // prototype so an upgrade does not ask the user to download it again.
      final legacy = File('${(await getApplicationSupportDirectory()).path}/local_ai_models/qwen2.5-0.5b-instruct-q4_k_m.gguf');
      if (await legacy.exists() && await legacy.length() > 450 * 1024 * 1024) {
        if (mounted) setState(() => _modelPath = legacy.path);
      }
    } catch (_) {}
  }

  Future<void> _downloadModel() async {
    if (_downloading || _busy) return;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _statusError = null;
    });
    File? file;
    IOSink? sink;
    try {
      file = await _modelFile();
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(_selectedPreset.url));
        request.followRedirects = true;
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Сервер модели вернул HTTP ${response.statusCode}.');
        }
        final total = response.contentLength;
        sink = file.openWrite();
        var received = 0;
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (mounted && total > 0) {
            setState(() => _downloadProgress = (received / total).clamp(0.0, 1.0).toDouble());
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
        final minimumBytes = (_selectedPreset == _LocalModelPreset.compact ? 95 : 320) * 1024 * 1024;
        if (await file.length() < minimumBytes) {
          throw const FormatException('Скачанный файл слишком мал и похож на страницу ошибки вместо GGUF-модели.');
        }
        if (mounted) {
          setState(() {
            _modelPath = file!.path;
            _downloadProgress = 1;
          });
        }
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      try { await sink?.close(); } catch (_) {}
      try { if (file != null && await file.exists()) await file.delete(); } catch (_) {}
      if (mounted) setState(() => _statusError = 'Не удалось скачать модель: $error');
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
        contextSize: 2048,
        nGpuLayers: 0,
      );
      await chat.loadModel(_modelPath!);
      _chatRepository = chat;
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
      setState(() {
        _statusError = 'Локальная модель не запустилась: $error';
        answerLine.text = 'Не удалось запустить модель на этом устройстве. Поиск кабинетов офлайн остаётся доступен.';
      });
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
                    const Text('Выбери размер локальной модели',
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
                      onChanged: _downloading ? null : (preset) {
                        if (preset != null) setState(() {
                          _selectedPreset = preset;
                          _statusError = null;
                          _downloadProgress = null;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(_selectedPreset.description),
                    const SizedBox(height: 5),
                    const Text('Модель не входит в APK. После однократной загрузки чат работает без интернета. Без скачанной модели поиск и навигация по встроенным данным остаются доступны офлайн.'),
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
                    const Expanded(child: Text('Модель сохранена на устройстве · интернет не нужен')),
                    if (_loadingModel)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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
