import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_security.dart';
import 'school_account_service.dart';

/// Голосования школы и класса. Создают сотрудники, голосуют все участники.
class PollsPage extends StatefulWidget {
  const PollsPage({super.key});

  @override
  State<PollsPage> createState() => _PollsPageState();
}

class _PollsPageState extends State<PollsPage> {
  List<Map<String, dynamic>> _polls = [];
  bool _loading = true;
  String? _error;
  String _base = '';
  String _token = '';
  String _role = '';
  String _classId = '';
  final Map<String, Set<String>> _selected = {};

  bool get _canCreate => const {'admin', 'teacher', 'mentor'}.contains(_role);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Uri _uri(String endpoint) {
    final parsed = Uri.parse(_base);
    var path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/api/v2')) {
      path = '$path/$endpoint';
    } else if (path.endsWith('/api')) {
      path = '$path/v2/$endpoint';
    } else {
      path = '$path/api/v2/$endpoint';
    }
    return parsed.replace(path: path, query: null, fragment: '', userInfo: '');
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final prefs = await SharedPreferences.getInstance();
      _base = (prefs.getString('school_api_base_url_v1') ??
              prefs.getString('navigator_api_url') ??
              '')
          .trim();
      final rawUser = prefs.getString('school_user_v1');
      if (rawUser != null) {
        try {
          final user = jsonDecode(rawUser);
          if (user is Map) {
            _role = '${user['role'] ?? ''}';
            _classId = '${user['class_id'] ?? ''}';
          }
        } catch (error) { debugPrint('polls_page: ${error.runtimeType}'); }
      }
      if (_base.isEmpty || !isSecureApiBaseUrl(_base)) {
        throw 'Сервер школы не настроен. Войди в школьный аккаунт в настройках.';
      }
      _token = (await SchoolAccountService().validAccessToken() ?? '').trim();
      if (_token.isEmpty) {
        throw 'Для голосований нужно войти в школьный аккаунт.';
      }
      final response = await http
          .get(_uri('polls'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw 'Сервер вернул ошибку ${response.statusCode}.';
      }
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      final rows = payload is Map ? payload['data'] : null;
      if (!mounted) return;
      setState(() {
        _polls = rows is List
            ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is String ? error : 'Не удалось загрузить голосования. Проверь соединение.';
      });
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send(Future<http.Response> Function() request, String failure) async {
    try {
      final response = await request().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var detail = failure;
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map && body['detail'] is String) detail = '$failure ${body['detail']}';
        } catch (error) { debugPrint('polls_page: ${error.runtimeType}'); }
        _message(detail);
        return;
      }
      await _load();
    } catch (_) {
      _message(failure);
    }
  }

  Future<void> _vote(Map<String, dynamic> poll) async {
    final id = '${poll['id']}';
    final chosen = _selected[id] ?? <String>{};
    if (chosen.isEmpty) return;
    await _send(
      () => http.post(
        _uri('polls/$id/vote'),
        headers: _headers,
        body: jsonEncode({'option_ids': chosen.toList()}),
      ),
      'Не удалось отправить голос.',
    );
    _selected.remove(id);
  }

  Future<void> _close(Map<String, dynamic> poll) => _send(
        () => http.post(_uri('polls/${poll['id']}/close'), headers: _headers),
        'Не удалось закрыть голосование.',
      );

  Future<void> _delete(Map<String, dynamic> poll) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Удалить голосование?'),
            content: const Text('Все голоса будут удалены.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Удалить')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _send(
      () => http.delete(_uri('polls/${poll['id']}'), headers: _headers),
      'Не удалось удалить голосование.',
    );
  }

  Future<void> _create() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CreatePollDialog(defaultClass: _classId),
    );
    if (created == null) return;
    await _send(
      () => http.post(_uri('polls'), headers: _headers, body: jsonEncode(created)),
      'Не удалось создать голосование.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Голосования')),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Создать'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  else if (_polls.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('Активных голосований пока нет',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  for (final poll in _polls) _pollCard(poll, scheme),
                ],
              ),
            ),
    );
  }

  Widget _pollCard(Map<String, dynamic> poll, ColorScheme scheme) {
    final id = '${poll['id']}';
    final open = poll['open'] == true;
    final multiple = poll['multiple'] == true;
    final mine = (poll['my_option_ids'] is List)
        ? (poll['my_option_ids'] as List).map((e) => '$e').toSet()
        : <String>{};
    final options = (poll['options'] is List)
        ? (poll['options'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final isClass = poll['scope'] == 'class';
    final accent = isClass ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);
    final canVote = open && mine.isEmpty;
    final showResults = !canVote;
    final total = options.fold<int>(0, (sum, o) => sum + ((o['votes'] as num?)?.toInt() ?? 0));
    final selected = _selected.putIfAbsent(id, () => <String>{});
    final description = '${poll['description'] ?? ''}'.trim();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isClass ? 'Класс ${poll['class_id']}' : 'Вся школа',
                      style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!open)
                    Text('Завершено',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  const Spacer(),
                  if (poll['can_manage'] == true)
                    PopupMenuButton<String>(
                      tooltip: 'Действия',
                      onSelected: (value) => value == 'close' ? _close(poll) : _delete(poll),
                      itemBuilder: (_) => [
                        if (open) const PopupMenuItem(value: 'close', child: Text('Завершить')),
                        const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('${poll['title']}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 10),
              if (canVote) ...[
                for (final option in options)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selected.contains('${option['id']}'),
                    title: Text('${option['text']}'),
                    onChanged: (value) => setState(() {
                      final optionId = '${option['id']}';
                      if (!multiple) selected.clear();
                      if (value == true) {
                        selected.add(optionId);
                      } else {
                        selected.remove(optionId);
                      }
                    }),
                  ),
                if (multiple)
                  Text('Можно выбрать несколько вариантов',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: selected.isEmpty ? null : () => _vote(poll),
                  child: const Text('Проголосовать'),
                ),
              ] else
                for (final option in options)
                  _resultRow(option, mine.contains('${option['id']}'), total, accent, scheme),
              if (showResults)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Проголосовало: ${poll['total_voters'] ?? 0}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultRow(Map<String, dynamic> option, bool mine, int total, Color accent, ColorScheme scheme) {
    final votes = (option['votes'] as num?)?.toInt() ?? 0;
    final share = total == 0 ? 0.0 : votes / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mine) ...[
                Icon(Icons.check_circle_rounded, size: 18, color: accent),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text('${option['text']}')),
              Text('$votes · ${(share * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 8,
              color: accent,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatePollDialog extends StatefulWidget {
  final String defaultClass;
  const _CreatePollDialog({required this.defaultClass});

  @override
  State<_CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<_CreatePollDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  late final TextEditingController _class =
      TextEditingController(text: widget.defaultClass);
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _classScope = false;
  bool _multiple = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _class.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    final options = _options.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (title.isEmpty) {
      setState(() => _error = 'Введи вопрос.');
      return;
    }
    if (options.length < 2) {
      setState(() => _error = 'Нужно минимум два варианта.');
      return;
    }
    if (options.map((e) => e.toLowerCase()).toSet().length != options.length) {
      setState(() => _error = 'Варианты не должны повторяться.');
      return;
    }
    if (_classScope && _class.text.trim().isEmpty) {
      setState(() => _error = 'Укажи класс, например 8А.');
      return;
    }
    Navigator.pop(context, {
      'title': title,
      'description': _description.text.trim(),
      'options': options,
      'scope': _classScope ? 'class' : 'school',
      if (_classScope) 'class_id': _class.text.trim(),
      'multiple': _multiple,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новое голосование'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Вопрос'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 2,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Пояснение (необязательно)'),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _options[i],
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: 'Вариант ${i + 1}',
                    counterText: '',
                    suffixIcon: _options.length > 2
                        ? IconButton(
                            tooltip: 'Убрать вариант',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              final removed = _options[i];
                              setState(() => _options.removeAt(i));
                              // TextField ещё в дереве до конца кадра.
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) => removed.dispose());
                            },
                          )
                        : null,
                  ),
                ),
              ),
            if (_options.length < 10)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _options.add(TextEditingController())),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Добавить вариант'),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Только для класса'),
              value: _classScope,
              onChanged: (value) => setState(() => _classScope = value),
            ),
            if (_classScope)
              TextField(
                controller: _class,
                decoration: const InputDecoration(labelText: 'Класс, например 8А'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Несколько ответов'),
              value: _multiple,
              onChanged: (value) => setState(() => _multiple = value),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _submit, child: const Text('Создать')),
      ],
    );
  }
}
