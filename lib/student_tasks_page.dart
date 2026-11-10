import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';

enum StudentTaskKind {
  homework('Домашнее задание', Icons.menu_book_rounded),
  test('Контрольная', Icons.quiz_rounded),
  project('Проект', Icons.assignment_rounded);
  const StudentTaskKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class StudentTask {
  const StudentTask({
    required this.id, required this.title, required this.subject,
    required this.description, required this.dueAt, required this.kind,
    required this.priority, required this.done, required this.createdAt,
  });
  final String id, title, subject, description;
  final DateTime dueAt, createdAt;
  final StudentTaskKind kind;
  final int priority;
  final bool done;

  StudentTask copyWith({bool? done}) => StudentTask(
    id: id, title: title, subject: subject, description: description,
    dueAt: dueAt, kind: kind, priority: priority, done: done ?? this.done,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'subject': subject, 'description': description,
    'due_at': dueAt.toIso8601String(), 'kind': kind.name, 'priority': priority,
    'done': done, 'created_at': createdAt.toIso8601String(),
  };

  factory StudentTask.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final kindName = (json['kind'] ?? '').toString();
    return StudentTask(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subject: (json['subject'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      dueAt: DateTime.tryParse((json['due_at'] ?? '').toString())?.toLocal() ?? now.add(const Duration(days: 1)),
      kind: StudentTaskKind.values.firstWhere((item) => item.name == kindName, orElse: () => StudentTaskKind.homework),
      priority: ((json['priority'] as num?)?.toInt() ?? 2).clamp(1, 3).toInt(),
      done: json['done'] == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString())?.toLocal() ?? now,
    );
  }
}

class StudentTaskStore {
  static const storageKey = 'pokolenie_student_tasks_v1';
  static const remindersKey = 'pokolenie_student_task_reminders_enabled';

  static Future<bool> remindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(remindersKey) ?? true;
  }

  static Future<void> setRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(remindersKey, enabled);
    final tasks = await load();
    await _scheduleReminders(enabled ? tasks : const <StudentTask>[]);
  }

  static Future<void> _scheduleReminders(List<StudentTask> tasks) async {
    try {
      await LocalNotificationService().scheduleUpcomingStudentTasks(
        entries: tasks.where((task) => !task.done).map((task) => (
          id: task.id,
          dueAt: task.dueAt,
          title: task.title,
          subject: task.subject,
        )).toList(),
      );
    } catch (_) {
      // Saving homework must remain available even when notification permission
      // is denied or a desktop platform notification backend is unavailable.
    }
  }

  static Future<List<StudentTask>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Список заданий имеет неизвестный формат.');
      }
      final tasks = decoded.whereType<Map>()
          .map((item) => StudentTask.fromJson(Map<String, dynamic>.from(item)))
          .where((task) => task.id.isNotEmpty && task.title.trim().isNotEmpty).toList();
      tasks.sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        final deadlineOrder = a.dueAt.compareTo(b.dueAt);
        if (deadlineOrder != 0) return deadlineOrder;
        return a.priority.compareTo(b.priority);
      });
      return tasks;
    } catch (error) {
      throw FormatException('Не удалось прочитать сохранённые задания: $error');
    }
  }

  static Future<void> save(List<StudentTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(storageKey, jsonEncode(tasks.map((task) => task.toJson()).toList()));
    if (!ok) throw StateError('Не удалось сохранить список заданий.');
    if (prefs.getBool(remindersKey) ?? true) {
      await _scheduleReminders(tasks);
    }
  }

  static Future<void> upsert(StudentTask task) async {
    final tasks = await load();
    final index = tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) { tasks.add(task); } else { tasks[index] = task; }
    await save(tasks);
  }

  static Future<bool> setCompleted(String id, bool done) async {
    final tasks = await load();
    final index = tasks.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    tasks[index] = tasks[index].copyWith(done: done);
    await save(tasks);
    return true;
  }

  static Future<bool> delete(String id) async {
    final tasks = await load();
    final before = tasks.length;
    tasks.removeWhere((task) => task.id == id);
    if (tasks.length == before) return false;
    await save(tasks);
    return true;
  }
}

enum _TaskFilter { all, active, today, overdue, completed }

class StudentTasksPage extends StatefulWidget {
  const StudentTasksPage({super.key, required this.onMenu});
  final VoidCallback onMenu;
  @override
  State<StudentTasksPage> createState() => _StudentTasksPageState();
}

class _StudentTasksPageState extends State<StudentTasksPage> {
  List<StudentTask> tasks = [];
  final TextEditingController _searchController = TextEditingController();
  bool loading = true;
  bool _remindersEnabled = true;
  String? _loadError;
  String _query = '';
  _TaskFilter filter = _TaskFilter.all;

  @override
  void initState() { super.initState(); _reload(); }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => loading = true);
    try {
      final results = await Future.wait<Object>([
        StudentTaskStore.load(),
        StudentTaskStore.remindersEnabled(),
      ]);
      if (!mounted) return;
      setState(() {
        tasks = results[0] as List<StudentTask>;
        _remindersEnabled = results[1] as bool;
        _loadError = null;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        loading = false;
      });
    }
  }

  Future<void> _toggleReminders(bool enabled) async {
    try {
      await StudentTaskStore.setRemindersEnabled(enabled);
      if (mounted) setState(() => _remindersEnabled = enabled);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить напоминания: $error')),
      );
    }
  }

  Future<void> _edit([StudentTask? initial]) async {
    final result = await showDialog<StudentTask>(
      context: context,
      builder: (_) => _TaskEditor(initial: initial),
    );
    if (result == null) return;
    try {
      await StudentTaskStore.upsert(result);
      await _reload();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $error')));
    }
  }

  Future<void> _toggle(StudentTask task, bool value) async {
    await StudentTaskStore.setCompleted(task.id, value);
    await _reload();
  }

  Future<void> _delete(StudentTask task) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задание?'),
        content: Text('«' + task.title + '» будет удалено с этого устройства.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (result == true) { await StudentTaskStore.delete(task.id); await _reload(); }
  }

  List<StudentTask> get visible {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final query = _query.trim().toLowerCase();
    final result = tasks.where((task) {
      if (query.isNotEmpty &&
          !task.title.toLowerCase().contains(query) &&
          !task.subject.toLowerCase().contains(query) &&
          !task.description.toLowerCase().contains(query)) {
        return false;
      }
      switch (filter) {
        case _TaskFilter.all: return true;
        case _TaskFilter.active: return !task.done;
        case _TaskFilter.today: return !task.done && !task.dueAt.isBefore(today) && task.dueAt.isBefore(tomorrow);
        case _TaskFilter.overdue: return !task.done && task.dueAt.isBefore(now);
        case _TaskFilter.completed: return task.done;
      }
    }).toList();
    result.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      final deadlineOrder = a.dueAt.compareTo(b.dueAt);
      if (deadlineOrder != 0) return deadlineOrder;
      return a.priority.compareTo(b.priority);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final todayCount = tasks.where((t) => !t.done && !t.dueAt.isBefore(today) && t.dueAt.isBefore(tomorrow)).length;
    final overdueCount = tasks.where((t) => !t.done && t.dueAt.isBefore(now)).length;
    final list = visible;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Домашние задания'),
        actions: [IconButton(onPressed: () => _edit(), tooltip: 'Добавить задание', icon: const Icon(Icons.add_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Добавить'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_problem_rounded, size: 44, color: scheme.error),
                          const SizedBox(height: 12),
                          const Text(
                            'Не удалось прочитать задания',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Сохранённые данные не были перезаписаны. Проверь хранилище приложения и повтори чтение. Ошибка: $_loadError',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.surfaceContainerHigh]),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Всё по учёбе — в одном месте', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('Домашние задания, контрольные и проекты. Сроки хранятся на этом устройстве.',
                      style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _SummaryPill('Сегодня', todayCount.toString(), scheme.tertiaryContainer),
                    _SummaryPill('Просрочено', overdueCount.toString(), scheme.errorContainer),
                    _SummaryPill('Активных', tasks.where((t) => !t.done).length.toString(), scheme.secondaryContainer),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Напоминать о сроках'),
                  subtitle: const Text('Операционная система покажет напоминание перед сдачей задания.'),
                  value: _remindersEnabled,
                  onChanged: _toggleReminders,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Поиск по заданию или предмету',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить поиск',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('Все', _TaskFilter.all),
                  _chip('Активные', _TaskFilter.active),
                  _chip('Сегодня', _TaskFilter.today),
                  _chip('Просроченные', _TaskFilter.overdue),
                  _chip('Выполнено', _TaskFilter.completed),
                ]),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
                  child: Column(children: [
                    Icon(Icons.task_alt_rounded, size: 52, color: scheme.primary),
                    const SizedBox(height: 12),
                    Text(tasks.isEmpty ? 'Список пока пуст' : 'Ничего не найдено',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                    const SizedBox(height: 6),
                    Text('Добавь домашнее задание, контрольную или проект и укажи срок сдачи.',
                        textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Добавить первое задание')),
                  ]),
                )
              else
                ...list.map((task) => _taskCard(task, scheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, _TaskFilter value) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ChoiceChip(label: Text(label), selected: filter == value, onSelected: (_) => setState(() => filter = value)),
  );

  Widget _taskCard(StudentTask task, ColorScheme scheme) {
    final overdue = !task.done && task.dueAt.isBefore(DateTime.now());
    final dateText = _formatDue(task.dueAt);
    final priorityColor = task.priority == 1 ? scheme.error : (task.priority == 2 ? scheme.tertiary : scheme.outline);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(task),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: task.done, onChanged: (value) => _toggle(task, value ?? false)),
            const SizedBox(width: 4),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.title, style: TextStyle(
                fontWeight: FontWeight.w900,
                decoration: task.done ? TextDecoration.lineThrough : null,
                color: task.done ? scheme.onSurfaceVariant : null,
              )),
              const SizedBox(height: 6),
              Wrap(spacing: 7, runSpacing: 6, children: [
                _TaskTag(task.kind.icon, task.kind.label),
                if (task.subject.isNotEmpty) _TaskTag(Icons.book_outlined, task.subject),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(overdue ? Icons.warning_amber_rounded : Icons.event_outlined, size: 16,
                    color: overdue ? scheme.error : scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Expanded(child: Text(dateText + ' · ' + _relativeDue(task.dueAt),
                    style: TextStyle(color: overdue ? scheme.error : scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700))),
                Icon(Icons.flag_rounded, size: 16, color: priorityColor),
              ]),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(task.description, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ])),
            PopupMenuButton<String>(
              tooltip: 'Действия',
              onSelected: (value) { if (value == 'edit') _edit(task); if (value == 'delete') _delete(task); },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Изменить')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(30)),
    child: Text(label + ': ' + value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
  );
}

class _TaskTag extends StatelessWidget {
  const _TaskTag(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({this.initial});
  final StudentTask? initial;
  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final TextEditingController title, subject, description;
  late DateTime dueAt;
  late StudentTaskKind kind;
  late int priority;

  @override
  void initState() {
    super.initState();
    final task = widget.initial;
    title = TextEditingController(text: task?.title ?? '');
    subject = TextEditingController(text: task?.subject ?? '');
    description = TextEditingController(text: task?.description ?? '');
    dueAt = task?.dueAt ?? DateTime.now().add(const Duration(days: 1));
    if (task == null) dueAt = DateTime(dueAt.year, dueAt.month, dueAt.day, 18);
    kind = task?.kind ?? StudentTaskKind.homework;
    priority = task?.priority ?? 2;
  }

  @override
  void dispose() { title.dispose(); subject.dispose(); description.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context, initialDate: dueAt,
      firstDate: DateTime(2020), lastDate: DateTime(2100),
    );
    if (value != null && mounted) setState(() => dueAt = DateTime(value.year, value.month, value.day, dueAt.hour, dueAt.minute));
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dueAt));
    if (value != null && mounted) setState(() => dueAt = DateTime(dueAt.year, dueAt.month, dueAt.day, value.hour, value.minute));
  }

  void _save() {
    final value = title.text.trim();
    if (value.isEmpty) return;
    final now = DateTime.now();
    final old = widget.initial;
    Navigator.pop(context, StudentTask(
      id: old?.id ?? now.microsecondsSinceEpoch.toString(),
      title: value, subject: subject.text.trim(), description: description.text.trim(),
      dueAt: dueAt, kind: kind, priority: priority, done: old?.done ?? false,
      createdAt: old?.createdAt ?? now,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Новое задание' : 'Изменить задание'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, autofocus: true, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Что нужно сделать?', hintText: 'Например: упражнения 12–15')),
          const SizedBox(height: 10),
          TextField(controller: subject, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Предмет', hintText: 'Например: алгебра')),
          const SizedBox(height: 10),
          DropdownButtonFormField<StudentTaskKind>(
            initialValue: kind, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Тип'),
            items: StudentTaskKind.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
            onChanged: (value) { if (value != null) setState(() => kind = value); },
          ),
          const SizedBox(height: 10),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Срок сдачи'),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_rounded), label: Text(_formatDue(dueAt).split(' · ').first)),
              OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule_rounded), label: Text(_two(dueAt.hour) + ':' + _two(dueAt.minute))),
            ]),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: priority,
            decoration: const InputDecoration(labelText: 'Важность'),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Срочно')),
              DropdownMenuItem(value: 2, child: Text('Обычно')),
              DropdownMenuItem(value: 3, child: Text('Можно позже')),
            ],
            onChanged: (value) { if (value != null) setState(() => priority = value); },
          ),
          const SizedBox(height: 10),
          TextField(controller: description, minLines: 2, maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Подробности', hintText: 'Страница, упражнение, что повторить…', alignLabelWithHint: true)),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: _save, child: const Text('Сохранить')),
    ],
  );
}

String _two(int value) => value.toString().padLeft(2, '0');
String _formatDue(DateTime value) {
  const months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  return value.day.toString() + ' ' + months[value.month - 1] + ' · ' + _two(value.hour) + ':' + _two(value.minute);
}
String _relativeDue(DateTime due) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final difference = day.difference(today).inDays;
  if (difference == 0) return 'сегодня';
  if (difference == 1) return 'завтра';
  if (difference == -1) return 'вчера';
  if (difference > 1) return 'через ' + difference.toString() + ' дн.';
  if (difference < -1) return 'просрочено на ' + (-difference).toString() + ' дн.';
  return '';
}
