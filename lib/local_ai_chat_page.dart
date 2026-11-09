import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path_provider/path_provider.dart';

/// On-device assistant. The GGUF model is stored outside the APK and runs locally.
class LocalAiChatPage extends StatefulWidget {
  final Future<String> Function(String question)? schoolContextLoader;

  const LocalAiChatPage({
    super.key,
    this.schoolContextLoader,
  });

  @override
  State<LocalAiChatPage> createState() => _LocalAiChatPageState();
}

class _ChatLine {
  final bool fromUser;
  String text;
  _ChatLine(this.fromUser, this.text);
}

class _LocalAiChatPageState extends State<LocalAiChatPage> {
  static const _modelFileName = 'qwen2.5-0.5b-instruct-q4_k_m.gguf';
  // Pin the model revision so the checksum always matches the downloaded file.
  static const _modelUrl =
      'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/12145bd1d629190a4d44254073650877954d02c9/qwen2.5-0.5b-instruct-q4_k_m.gguf';
  static const _modelSha256 =
      '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db';
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
        'Привет! Я локальный ИИ-помощник. Поиск кабинета по встроенной карте работает офлайн. Для свободного диалога сначала нужно скачать небольшую модель (~491 МБ); после этого интернет не потребуется.')
  ];
  final List<LLMMessage> _history = [
    LLMMessage(role: LLMRole.system, content: _systemPrompt),
  ];

  LlamaCppRepository? _modelRepository;
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

  Future<File> _modelFile() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/local_ai_models');
    await directory.create(recursive: true);
    return File('${directory.path}/$_modelFileName');
  }

  Future<void> _writeModelVerificationMarker(File file) async {
    final stat = await file.stat();
    final marker = File('${file.path}.verified');
    final value =
        '$_modelSha256:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    await marker.writeAsString(value, flush: true);
  }

  Future<void> _findExistingModel() async {
    try {
      final file = await _modelFile();
      if (!await file.exists() || await file.length() < 400 * 1024 * 1024) {
        return;
      }

      final handle = await file.open();
      late final List<int> header;
      try {
        header = await handle.read(4);
      } finally {
        await handle.close();
      }

      if (String.fromCharCodes(header) != 'GGUF') {
        throw const FormatException('Файл не имеет формата GGUF.');
      }

      final stat = await file.stat();
      final marker = File('${file.path}.verified');
      final expectedMarker =
          '$_modelSha256:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      final markerIsValid = await marker.exists() &&
          (await marker.readAsString()).trim() == expectedMarker;

      // Hash the large model on first use and whenever its size or modification
      // time changes. Normal app launches then avoid reading 491 MB again.
      if (!markerIsValid) {
        final digest = await crypto.sha256.bind(file.openRead()).first;
        if (digest.toString() != _modelSha256) {
          throw const FormatException(
            'Контрольная сумма сохранённой модели не совпадает.',
          );
        }
        await marker.writeAsString(expectedMarker, flush: true);
      }

      if (mounted) setState(() => _modelPath = file.path);
    } catch (error) {
      if (mounted) {
        setState(() => _statusError = 'Не удалось проверить локальную модель: $error');
      }
    }
  }

  Future<void> _downloadModel() async {
    if (_downloading || _busy || !mounted) return;

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _statusError = null;
    });

    File? modelFile;
    File? partialFile;
    File? backupFile;
    IOSink? sink;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      modelFile = await _modelFile();
      partialFile = File('${modelFile.path}.part');
      backupFile = File('${modelFile.path}.backup');

      // A previous interrupted attempt must never be mistaken for a model.
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      final request = await client
          .getUrl(Uri.parse(_modelUrl))
          .timeout(const Duration(seconds: 30));
      request
        ..followRedirects = true
        ..maxRedirects = 5;

      final response = await request.close().timeout(
            const Duration(minutes: 2),
          );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Сервер модели вернул HTTP ${response.statusCode}.',
        );
      }

      final expectedLength = response.contentLength;
      const minimumModelSize = 400 * 1024 * 1024;
      if (expectedLength > 0 && expectedLength < minimumModelSize) {
        throw const FormatException(
          'Сервер вернул файл неожиданно маленького размера.',
        );
      }

      sink = partialFile.openWrite();
      var received = 0;

      await for (final chunk in response.timeout(
        const Duration(minutes: 2),
      )) {
        sink.add(chunk);
        received += chunk.length;

        if (mounted && expectedLength > 0) {
          setState(() {
            _downloadProgress =
                (received / expectedLength).clamp(0.0, 1.0).toDouble();
          });
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      final actualLength = await partialFile.length();
      if (actualLength < minimumModelSize ||
          (expectedLength > 0 && actualLength != expectedLength)) {
        throw const FormatException(
          'Размер скачанного файла не совпадает с ожидаемым.',
        );
      }

      final digest = await crypto.sha256.bind(partialFile.openRead()).first;
      if (digest.toString() != _modelSha256) {
        throw const FormatException(
          'Контрольная сумма модели не совпадает. Файл повреждён.',
        );
      }

      // Keep the previous file recoverable until the verified download is in
      // place. This also avoids exposing a half-downloaded model to the app.
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      final hadPreviousModel = await modelFile.exists();
      if (hadPreviousModel) {
        await modelFile.rename(backupFile.path);
      }

      try {
        await partialFile.rename(modelFile.path);
        try {
          await _writeModelVerificationMarker(modelFile);
        } catch (_) {
          // The download was already hash-verified. Without a marker, the next
          // app launch safely rechecks the checksum once.
        }
        if (hadPreviousModel && await backupFile.exists()) {
          await backupFile.delete();
        }
      } catch (_) {
        if (hadPreviousModel && await backupFile.exists()) {
          await backupFile.rename(modelFile.path);
        }
        rethrow;
      }

      if (mounted) {
        setState(() {
          _modelPath = modelFile!.path;
          _downloadProgress = 1;
        });
      }
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (partialFile != null && await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _statusError = 'Не удалось скачать модель: $error';
        });
      }
    } finally {
      client.close(force: true);
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _ensureLoaded() async {
    if (_chatRepository != null) return;
    final modelPath = _modelPath;
    if (modelPath == null) {
      throw StateError('Сначала скачай модель. Это делается один раз.');
    }

    if (mounted) setState(() => _loadingModel = true);
    final repository = LlamaCppRepository();
    try {
      final model = await repository.loadModel(modelPath);
      final chat = LlamaCppChatRepository.withModel(
        model,
        repository.bindings,
        contextSize: 2048,
        nGpuLayers: 0,
      );
      _modelRepository = repository;
      _chatRepository = chat;
    } catch (_) {
      // Do not leak the native model repository if loading or chat setup fails.
      repository.dispose();
      rethrow;
    } finally {
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  void _trimConversationHistory() {
    // Preserve complete user/assistant pairs and always keep the system prompt.
    const maximumConversationMessages = 6;
    final conversationLength = _history.length - 1;
    final overflow = conversationLength - maximumConversationMessages;
    if (overflow <= 0) return;

    final messagesToRemove = ((overflow + 1) ~/ 2) * 2;
    _history.removeRange(1, 1 + messagesToRemove);
  }

  String? _offlineRoomAnswer(String text) {
    final query = text.toLowerCase();
    final match = RegExp(r'(?<!\d)(\d{3}(?:\.\d+)?)(?!\d)').firstMatch(query);
    if (match != null) {
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
    const placeKeywords = <String, List<String>>{
      'библиотек': ['place_library'],
      'столов': ['place_canteen'],
      'пищеблок': ['place_food'],
      'бассейн': ['place_pool'],
      'тренажер': ['place_gym'],
      'тренажёр': ['place_gym'],
      'спортзал': ['place_sport', 'place_gym'],
      'спортивн': ['place_sport'],
      'хореограф': ['place_choreo'],
      'акт': ['place_auditorium'],
      'террас': ['place_terrace'],
      'дрон': ['place_drone'],
      'инженер': ['place_engineering'],
      'бактери': ['place_bio_lab'],
      'гример': ['place_dressing'],
      'гримёр': ['place_dressing'],
      'сцен': ['place_stage'],
    };

    for (final entry in placeKeywords.entries) {
      if (!query.contains(entry.key)) continue;
      final matches = _places
          .where((place) => entry.value.contains(place['id']))
          .toList();
      if (matches.length == 1) {
        final place = matches.single;
        final floor = place['floor'];
        return 'По встроенной карте найдено: ${place['name']}.'
            '${floor == null ? '' : ' Этаж: $floor.'} '
            'Чтобы построить проверенный маршрут, открой «Карта школы» и выбери эту точку.';
      }
      if (matches.length > 1) {
        final names = matches.map((place) => place['name']).join(' или ');
        return 'На карте есть несколько подходящих мест: $names. Уточни, куда именно нужно попасть.';
      }
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
    if (!mounted) return;

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

      var schoolContext = '';
      try {
        schoolContext = await widget.schoolContextLoader?.call(text) ?? '';
      } catch (error) {
        if (mounted) {
          setState(() {
            _statusError = 'Не удалось прочитать локальное расписание: $error';
          });
        }
      }
      if (!mounted) return;

      _history.add(LLMMessage(role: LLMRole.user, content: text));
      _trimConversationHistory();

      final systemContent = schoolContext.isEmpty
          ? _systemPrompt
          : '$_systemPrompt\n\n'
              'АКТУАЛЬНЫЕ ЛОКАЛЬНЫЕ ДАННЫЕ «ПОКОЛЕНИЯ» (используй как источник фактов):\n'
              '$schoolContext\n'
              'Отвечай только на основе этих данных. Не делай выводов о занятиях, '
              'которых здесь нет. Если расписание не содержит нужной информации, '
              'прямо скажи, что она не указана.';

      final messages = <LLMMessage>[
        LLMMessage(role: LLMRole.system, content: systemContent),
        ..._history.skip(1),
      ];
      final repo = _chatRepository!;
      await for (final chunk in repo.streamChat(_modelPath!, messages: messages)) {
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
      _trimConversationHistory();
    } catch (error) {
      answerLine.text =
          'Не удалось запустить модель на этом устройстве. Поиск кабинетов офлайн остаётся доступен.';
      _history.add(LLMMessage(
        role: LLMRole.assistant,
        content: answerLine.text,
      ));
      _trimConversationHistory();
      if (mounted) {
        setState(() {
          _statusError = 'Локальная модель не запустилась: $error';
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
    _modelRepository?.dispose();
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
                    const Text('Модель Qwen2.5 0.5B · Q4_K_M',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    const Text('Около 491 МБ. Модель не входит в APK, чтобы не раздувать установщик. После однократной загрузки чат работает без интернета. На слабых устройствах ответы могут генерироваться медленно.'),
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
