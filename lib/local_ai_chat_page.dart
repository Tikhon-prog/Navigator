import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path_provider/path_provider.dart';

typedef _LocalAiActionHandler = Future<String> Function(
  String action,
  Map<String, dynamic> arguments,
);
typedef _LocalAiRouteHandler = Future<void> Function(String destinationId, String? originId);

class _LocalAiTool extends LLMTool {
  _LocalAiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
  });

  @override
  final String name;
  @override
  final String description;
  @override
  final List<LLMToolParam> parameters;

  final _LocalAiActionHandler handler;

  @override
  Future<String> execute(
    Map<String, dynamic> args, {
    dynamic extra,
  }) {
    return handler(name, args);
  }
}

/// On-device assistant. The GGUF model is stored outside the APK and runs locally.
class LocalAiChatPage extends StatefulWidget {
  final Future<String> Function(String question)? schoolContextLoader;
  final _LocalAiActionHandler? actionHandler;
  final ValueChanged<String>? onOpenMapLocation;
  final _LocalAiRouteHandler? onOpenSchoolRoute;

  const LocalAiChatPage({
    super.key,
    this.schoolContextLoader,
    this.actionHandler,
    this.onOpenMapLocation,
    this.onOpenSchoolRoute,
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
  // Keep the native engine alive across chat-page closes and screen changes.
  // llama.cpp itself performs inference in a worker isolate.
  static LlamaCppRepository? _sharedModelRepository;
  static LlamaCppChatRepository? _sharedChatRepository;
  static String? _sharedModelPath;
  static Future<void>? _sharedLoadFuture;

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
Перед ответами о домашних заданиях используй get_student_tasks. Для новых заданий не выдумывай срок: если дата или время не названы либо неоднозначны, сначала уточни их. Перед удалением или отметкой выполнения сначала найди точный ID задания. Для удаления ДОПа или задания приложение обязательно запросит отдельное подтверждение пользователя.
Если пользователь просит построить маршрут, обязательно вызови инструмент plan_school_route. Не выдумывай коридоры и лестницы. Если просит добавить кабинет в избранное или убрать его, вызови set_favorite_location. Открывай найденную точку через open_school_location. Изменяй расписание, ДОПы, задания, избранное и настройки только через инструменты приложения.
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
  bool _checkingModel = false;
  double? _downloadProgress;
  String? _pendingOpenMapLocationId;
  String? _pendingOpenSchoolRouteId;
  String? _pendingOpenSchoolRouteOriginId;
  String _selectedCategory = 'Навигация';
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
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}local_ai_models',
    );
    await directory.create(recursive: true);
    if (!await directory.exists()) {
      throw FileSystemException(
        'Не удалось создать каталог локальной модели.',
        directory.path,
      );
    }
    return File(
      '${directory.path}${Platform.pathSeparator}$_modelFileName',
    );
  }

  Future<void> _writeModelVerificationMarker(File file) async {
    final stat = await file.stat();
    final marker = File('${file.path}.verified');
    final value =
        '$_modelSha256:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    await marker.writeAsString(value, flush: true);
  }

  Future<void> _findExistingModel() async {
    if (mounted) setState(() => _checkingModel = true);
    try {
      final file = await _modelFile();
      if (!await file.exists() ||
          await file.length() < 400 * 1024 * 1024) {
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
        setState(() {
          _statusError = 'Не удалось проверить локальную модель: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _checkingModel = false);
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
    RandomAccessFile? writer;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..userAgent = 'PokolenieSchoolApp/0.2';

    try {
      modelFile = await _modelFile();
      partialFile = File('${modelFile.path}.part');
      backupFile = File('${modelFile.path}.backup');

      // Explicitly create the parent and the temporary file. This avoids
      // asking File.length() about a path that was never materialized.
      await partialFile.parent.create(recursive: true);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      await partialFile.create(recursive: true);
      writer = await partialFile.open(mode: FileMode.write);

      final request = await client
          .getUrl(Uri.parse(_modelUrl))
          .timeout(const Duration(seconds: 30));
      request
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');

      final response = await request.close().timeout(
            const Duration(minutes: 2),
          );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Сервер модели вернул HTTP ${response.statusCode}.',
          response.uri,
        );
      }

      final expectedLength = response.contentLength;
      const minimumModelSize = 400 * 1024 * 1024;
      if (expectedLength == 0 ||
          (expectedLength > 0 && expectedLength < minimumModelSize)) {
        throw const FormatException(
          'Сервер вернул пустой или слишком маленький файл модели. '
          'Проверь доступ к Hugging Face и повтори загрузку.',
        );
      }
      if (mounted) {
        setState(() => _downloadProgress = expectedLength > 0 ? 0 : null);
      }

      var received = 0;
      await for (final chunk in response.timeout(
        const Duration(minutes: 3),
      )) {
        if (chunk.isEmpty) continue;
        await writer.writeFrom(chunk);
        received += chunk.length;

        if (mounted && expectedLength > 0) {
          setState(() {
            _downloadProgress =
                (received / expectedLength).clamp(0.0, 1.0).toDouble();
          });
        }
      }

      await writer.flush();
      await writer.close();
      writer = null;

      if (!await partialFile.exists()) {
        throw FileSystemException(
          'Временный файл модели не был создан после загрузки.',
          partialFile.path,
        );
      }

      final actualLength = await partialFile.length();
      if (received == 0 ||
          actualLength < minimumModelSize ||
          actualLength != received ||
          (expectedLength > 0 && actualLength != expectedLength)) {
        throw FormatException(
          'Загрузка модели неполная: получено ${actualLength} байт'
          '${expectedLength > 0 ? ' из $expectedLength' : ''}.',
        );
      }

      final digest = await crypto.sha256.bind(partialFile.openRead()).first;
      if (digest.toString() != _modelSha256) {
        throw const FormatException(
          'Контрольная сумма модели не совпадает. Файл повреждён.',
        );
      }

      // Keep the previous file recoverable until the verified download is in
      // place. Never replace a working model with an unverified download.
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
          _statusError = null;
        });
      }
    } catch (error) {
      try {
        await writer?.close();
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
    final modelPath = _modelPath;
    if (modelPath == null) {
      throw StateError('Сначала скачай модель. Это делается один раз.');
    }

    if (_sharedChatRepository != null && _sharedModelPath == modelPath) {
      _modelRepository = _sharedModelRepository;
      _chatRepository = _sharedChatRepository;
      return;
    }

    final activeLoad = _sharedLoadFuture;
    if (activeLoad != null) {
      await activeLoad;
      if (_sharedChatRepository != null && _sharedModelPath == modelPath) {
        _modelRepository = _sharedModelRepository;
        _chatRepository = _sharedChatRepository;
        return;
      }
    }

    final load = _loadSharedModel(modelPath);
    _sharedLoadFuture = load;
    if (mounted) setState(() => _loadingModel = true);
    try {
      await load;
      _modelRepository = _sharedModelRepository;
      _chatRepository = _sharedChatRepository;
    } finally {
      if (identical(_sharedLoadFuture, load)) _sharedLoadFuture = null;
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  static Future<void> _loadSharedModel(String modelPath) async {
    final oldChat = _sharedChatRepository;
    final oldRepository = _sharedModelRepository;
    _sharedChatRepository = null;
    _sharedModelRepository = null;
    oldChat?.dispose();
    oldRepository?.dispose();

    final repository = LlamaCppRepository();
    try {
      final model = await repository.loadModel(modelPath);
      final chat = LlamaCppChatRepository.withModel(
        model,
        repository.bindings,
        contextSize: 4096,
        nGpuLayers: 0,
      );
      _sharedModelRepository = repository;
      _sharedChatRepository = chat;
      _sharedModelPath = modelPath;
    } catch (_) {
      repository.dispose();
      _sharedModelPath = null;
      rethrow;
    }
  }

  Future<bool> _confirmDestructiveAction(
    String action,
    Map<String, dynamic> args,
  ) async {
    if (!mounted) return false;

    final isSupplement = action == 'delete_supplement';
    final subject = (args[isSupplement ? 'title' : 'id'] ?? '')
        .toString()
        .trim();
    if (subject.isEmpty) return false;

    final description = isSupplement
        ? 'Удалить локальное дополнительное занятие «$subject»?'
        : 'Удалить задание с ID $subject с этого устройства?';

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Подтвердить удаление'),
            content: Text(
              '$description\\n\\nЭто действие нельзя автоматически отменить.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Не удалять'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String> _runAction(String name, Map<String, dynamic> args) async {
    final handler = widget.actionHandler;
    if (handler == null) {
      return 'Действия приложения пока не подключены в этой сборке.';
    }
    if (name == 'delete_supplement' || name == 'delete_student_task') {
      final approved = await _confirmDestructiveAction(name, args);
      if (!approved) {
        return 'Пользователь отменил удаление. Не повторяй это действие без нового прямого запроса.';
      }
    }
    final result = await handler(name, args);
    final mapPrefix = '__OPEN_MAP__:';
    if (result.startsWith(mapPrefix)) {
      _pendingOpenMapLocationId = result.substring(mapPrefix.length).trim();
      return 'Точка найдена. После ответа открою её на карте школы.';
    }
    const routePrefix = '__OPEN_ROUTE__:';
    if (result.startsWith(routePrefix)) {
      final separator = result.indexOf('\n');
      final routeData = result.substring(
        routePrefix.length,
        separator < 0 ? result.length : separator,
      ).trim();
      final parts = routeData.split('|');
      _pendingOpenSchoolRouteId = parts.first.trim();
      _pendingOpenSchoolRouteOriginId =
          parts.length > 1 && parts[1].trim().isNotEmpty
              ? parts[1].trim()
              : null;
      final details = separator < 0 ? '' : result.substring(separator + 1).trim();
      return details.isEmpty
          ? 'Маршрут найден по школьной карте. Сейчас открою его.'
          : details;
    }
    return result;
  }
  List<LLMTool> _buildTools() => [
        _LocalAiTool(
          name: 'get_school_context',
          description:
              'Получить расписание ученика, группы, ДОПы и локальные сведения школы. Используй перед ответами на вопросы о занятиях.',
          parameters: [
            LLMToolParam(
              name: 'question',
              type: 'string',
              description: 'Период или тема: неделя, сегодня, завтра, вторник',
              isRequired: true,
            ),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'search_school_map',
          description:
              'Найти кабинет или объект на встроенной карте школы по номеру или названию.',
          parameters: [
            LLMToolParam(
              name: 'query',
              type: 'string',
              description: 'Номер кабинета или название места',
              isRequired: true,
            ),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'set_favorite_location',
          description:
              'Добавить кабинет или место в избранное либо убрать его оттуда. Сначала найди точный ID через search_school_map.',
          parameters: [
            LLMToolParam(name: 'location_id', type: 'string', description: 'Точный ID помещения из школьной карты', isRequired: true),
            LLMToolParam(name: 'favorite', type: 'string', description: 'true/да — добавить; false/нет — убрать', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'plan_school_route',
          description:
              'Построить настоящий маршрут по графу коридоров школы и показать его на карте. Обязательно используй при просьбе пройти/дойти/построить путь.',
          parameters: [
            LLMToolParam(
              name: 'destination',
              type: 'string',
              description: 'Номер кабинета или название места назначения',
              isRequired: true,
            ),
            LLMToolParam(
              name: 'origin',
              type: 'string',
              description: 'Откуда начать: номер кабинета или место. Пустая строка использует сохранённую точку старта',
              isRequired: false,
            ),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'open_school_location',
          description:
              'Открыть найденный кабинет или объект в разделе карты приложения.',
          parameters: [
            LLMToolParam(
              name: 'location_id',
              type: 'string',
              description: 'Точный ID точки, полученный из поиска по карте',
              isRequired: true,
            ),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'set_math_lesson_name',
          description:
              'Переименовать конкретный математический урок выбранного класса: геометрия, алгебра или вероятность и статистика.',
          parameters: [
            LLMToolParam(name: 'day', type: 'string', description: 'День недели', isRequired: true),
            LLMToolParam(name: 'lesson_number', type: 'integer', description: 'Порядковый номер урока математики в этот день, начиная с 1', isRequired: true),
            LLMToolParam(name: 'subject', type: 'string', description: 'Алгебра, Геометрия, Вероятность и статистика или пустая строка для сброса', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'set_subject_group',
          description:
              'Выбрать учебную группу по конкретному предмету для расписания ученика.',
          parameters: [
            LLMToolParam(name: 'subject', type: 'string', description: 'Название предмета', isRequired: true),
            LLMToolParam(name: 'group', type: 'integer', description: 'Номер доступной группы', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'set_route_start',
          description:
              'Установить начальную точку построения маршрутов: главный вход или проверенное место на одном из этажей.',
          parameters: [
            LLMToolParam(name: 'floor', type: 'integer', description: 'Этаж 1, 2 или 3', isRequired: true),
            LLMToolParam(name: 'location_id', type: 'string', description: 'ID точки старта; пустая строка означает главный вход', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'save_personal_note',
          description: 'Сохранить личную заметку на этом устройстве.',
          parameters: [
            LLMToolParam(name: 'title', type: 'string', description: 'Заголовок заметки', isRequired: true),
            LLMToolParam(name: 'body', type: 'string', description: 'Содержимое заметки', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'add_supplement',
          description:
              'Добавить локальный кружок или дополнительное занятие в список ДОПов. Не выдумывай время и кабинет.',
          parameters: [
            LLMToolParam(name: 'title', type: 'string', description: 'Название занятия', isRequired: true),
            LLMToolParam(name: 'day', type: 'string', description: 'День недели', isRequired: true),
            LLMToolParam(name: 'start', type: 'string', description: 'Время начала HH:mm или пусто, если неизвестно', isRequired: true),
            LLMToolParam(name: 'end', type: 'string', description: 'Время окончания HH:mm или пусто, если неизвестно', isRequired: true),
            LLMToolParam(name: 'room', type: 'string', description: 'Кабинет или пусто', isRequired: true),
            LLMToolParam(name: 'teacher', type: 'string', description: 'Преподаватель или пусто', isRequired: true),
            LLMToolParam(name: 'description', type: 'string', description: 'Описание или пусто', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'delete_supplement',
          description: 'Удалить локальный ДОП по его точному названию.',
          parameters: [
            LLMToolParam(name: 'title', type: 'string', description: 'Точное название занятия', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'get_student_tasks',
          description: 'Прочитать домашние задания, контрольные и проекты ученика. Вызывай перед вопросами о дедлайнах и перед изменением существующего задания.',
          parameters: [
            LLMToolParam(name: 'filter', type: 'string', description: 'all, active, today, overdue или completed', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'add_student_task',
          description: 'Создать домашнее задание, контрольную или проект в локальном списке. Если срок неясен, сначала спроси дату и время, не выдумывай дедлайн.',
          parameters: [
            LLMToolParam(name: 'title', type: 'string', description: 'Что нужно сделать', isRequired: true),
            LLMToolParam(name: 'subject', type: 'string', description: 'Предмет или пустая строка', isRequired: true),
            LLMToolParam(name: 'due_at', type: 'string', description: 'Точная дата и время в ISO 8601 local time, например 2026-11-12T18:00:00', isRequired: true),
            LLMToolParam(name: 'kind', type: 'string', description: 'homework, test или project', isRequired: true),
            LLMToolParam(name: 'priority', type: 'integer', description: '1 срочно, 2 обычно, 3 можно позже', isRequired: true),
            LLMToolParam(name: 'description', type: 'string', description: 'Страница, упражнения или дополнительные детали', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'complete_student_task',
          description: 'Отметить задание выполненным. Сначала найди точный ID через get_student_tasks.',
          parameters: [
            LLMToolParam(name: 'id', type: 'string', description: 'ID задания из локального списка', isRequired: true),
          ],
          handler: _runAction,
        ),
        _LocalAiTool(
          name: 'delete_student_task',
          description: 'Удалить задание по точному ID. Сначала найди его через get_student_tasks.',
          parameters: [
            LLMToolParam(name: 'id', type: 'string', description: 'ID задания из локального списка', isRequired: true),
          ],
          handler: _runAction,
        ),
      ];

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

  static const Map<String, List<String>> _categoryPrompts = {
    'Навигация': [
      'Построй маршрут до кабинета 317',
      'Найди библиотеку и открой её на карте',
      'Построй маршрут от кабинета 215 до кабинета 319',
      'Добавь кабинет 317 в избранное',
    ],
    'Расписание': [
      'Покажи моё расписание на завтра',
      'Сколько уроков математики в среду?',
      'Переименуй второй урок математики во вторник в геометрию',
    ],
    'ДОПы': [
      'Покажи мои дополнительные занятия на неделю',
      'Добавь программирование по средам в мои ДОПы',
      'Какие у меня ближайшие дополнительные занятия?',
    ],
    'Задания': [
      'Что мне нужно сдать сегодня?',
      'Добавь домашнее задание по алгебре на завтра к 18:00',
      'Какие контрольные и проекты у меня скоро?',
    ],
    'Заметки': [
      'Сохрани заметку: подготовиться к контрольной по алгебре',
      'Как посмотреть мои заметки?',
    ],
    'Настройки': [
      'Установи главный вход начальной точкой маршрута',
      'Объясни, как настроить учебные группы',
    ],
    'Помощь': [
      'Что ты умеешь делать?',
      'Какие данные ты используешь и что работает без интернета?',
    ],
  };

  void _sendPrompt(String prompt) {
    if (_busy || _downloading || _loadingModel) return;
    _input.text = prompt;
    _send();
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

    final lowerQuery = text.toLowerCase();
    final asksForRoute = lowerQuery.contains('маршрут') ||
        lowerQuery.contains('пролож') ||
        lowerQuery.contains('как пройти') ||
        lowerQuery.contains('как дойти') ||
        lowerQuery.contains('как попасть') ||
        lowerQuery.contains('доведи') ||
        lowerQuery.contains('построй путь') ||
        lowerQuery.contains('путь до') ||
        lowerQuery.contains('путь от') ||
        lowerQuery.contains('пройти до') ||
        lowerQuery.contains('дойди до');
    final asksForAction = asksForRoute ||
        lowerQuery.contains('добавь') ||
        lowerQuery.contains('добавить') ||
        lowerQuery.contains('в избранное') ||
        lowerQuery.contains('избранного') ||
        lowerQuery.contains('избранное') ||
        lowerQuery.contains('избран') ||
        lowerQuery.contains('убери') ||
        lowerQuery.contains('убрать') ||
        lowerQuery.contains('удали') ||
        lowerQuery.contains('удалить') ||
        lowerQuery.contains('сохрани') ||
        lowerQuery.contains('сохранить') ||
        lowerQuery.contains('измени') ||
        lowerQuery.contains('изменить') ||
        lowerQuery.contains('переименуй') ||
        lowerQuery.contains('установи') ||
        lowerQuery.contains('установить') ||
        lowerQuery.contains('выбери') ||
        lowerQuery.contains('выбрать') ||
        lowerQuery.contains('отметь') ||
        lowerQuery.contains('выполнено') ||
        lowerQuery.contains('открой') ||
        lowerQuery.contains('открыть') ||
        lowerQuery.contains('запиши') ||
        lowerQuery.contains('создай');
    final offlineAnswer = asksForAction ? null : _offlineRoomAnswer(text);
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
      String? rawAssistantTurn;
      await for (final chunk in repo.streamChat(
        _modelPath!,
        messages: messages,
        tools: _buildTools(),
        options: const LLMChatOptions(toolAttempts: 4),
      )) {
        final message = chunk.message;
        if (message?.rawContent.isNotEmpty == true) {
          rawAssistantTurn = message!.rawContent;
        }
        final part = message?.content ?? '';
        if (part.isNotEmpty && mounted) {
          answerLine.text += part;
          setState(() {});
          _scrollToBottom();
        }
      }
      if (answerLine.text.trim().isEmpty) {
        answerLine.text = 'Модель не вернула ответ. Попробуй сформулировать вопрос короче.';
      }
      _history.add(LLMMessage(
        role: LLMRole.assistant,
        content: rawAssistantTurn ?? answerLine.text,
      ));
      _trimConversationHistory();
      final openRouteId = _pendingOpenSchoolRouteId;
      final openRouteOriginId = _pendingOpenSchoolRouteOriginId;
      _pendingOpenSchoolRouteId = null;
      _pendingOpenSchoolRouteOriginId = null;
      if (openRouteId != null && mounted) {
        final routeHandler = widget.onOpenSchoolRoute;
        if (routeHandler != null) {
          await routeHandler(openRouteId, openRouteOriginId);
          return;
        }
      }
      final openLocationId = _pendingOpenMapLocationId;
      _pendingOpenMapLocationId = null;
      if (openLocationId != null && mounted) {
        widget.onOpenMapLocation?.call(openLocationId);
        Navigator.of(context).pop();
      }
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
    // The shared native model is intentionally kept alive while the app process
    // is running, so switching screens does not unload/reload 491 MB every time.
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
                    if (_checkingModel && !_downloading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 5),
                      const Text('Проверяем, есть ли модель на устройстве…'),
                    ] else if (_downloading) ...[
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
            SizedBox(
              height: 44,
              child: Scrollbar(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final category in _categoryPrompts.keys)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          onSelected: _busy || _downloading
                              ? null
                              : (_) => setState(() => _selectedCategory = category),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                itemCount: _categoryPrompts[_selectedCategory]!.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) => ActionChip(
                  label: Text(
                    _categoryPrompts[_selectedCategory]![index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _busy || _downloading
                      ? null
                      : () => _sendPrompt(_categoryPrompts[_selectedCategory]![index]),
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                interactive: true,
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
