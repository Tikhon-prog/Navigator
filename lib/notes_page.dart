import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersonalNotesPage extends StatefulWidget {
  const PersonalNotesPage({super.key});

  @override
  State<PersonalNotesPage> createState() => _PersonalNotesPageState();
}

class _PersonalNote {
  const _PersonalNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory _PersonalNote.fromJson(Map<String, dynamic> json) => _PersonalNote(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? 'Заметка').toString(),
        body: (json['body'] ?? '').toString(),
        updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({this.note});

  final _PersonalNote? note;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _bodyController = TextEditingController(text: widget.note?.body ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.note == null ? 'Новая заметка' : 'Редактировать заметку'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('note-title-input'),
              controller: _titleController,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Заголовок',
                hintText: 'Например, подготовка к контрольной',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('note-body-input'),
              controller: _bodyController,
              minLines: 4,
              maxLines: 10,
              maxLength: 4000,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Текст заметки',
                alignLabelWithHint: true,
                hintText: 'Что нужно запомнить?',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            final body = _bodyController.text.trim();
            if (title.isEmpty && body.isEmpty) return;
            final effectiveTitle = title.isEmpty
                ? (body.length > 40 ? '${body.substring(0, 40)}…' : body)
                : title;
            Navigator.pop(
              context,
              (title: effectiveTitle, body: body),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _PersonalNotesPageState extends State<PersonalNotesPage> {
  static const _baseStorageKey = 'pokolenie_personal_notes_v1';
  final List<_PersonalNote> _notes = [];
  bool _loading = true;
  String _storageKey = '${_baseStorageKey}_local';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var accountId = '';
    final rawAccount = prefs.getString('school_user_v1');
    if (rawAccount != null && rawAccount.trim().isNotEmpty) {
      try {
        final account = jsonDecode(rawAccount);
        if (account is Map && account['id'] != null) {
          accountId = account['id'].toString().trim();
        }
      } catch (_) {}
    }
    final safeId = accountId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    _storageKey = '${_baseStorageKey}_${safeId.isEmpty ? 'local' : safeId}';
    final stored = prefs.getString(_storageKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        final decoded = jsonDecode(stored);
        if (decoded is List) {
          _notes
            ..clear()
            ..addAll(decoded.whereType<Map>().map(
              (item) => _PersonalNote.fromJson(Map<String, dynamic>.from(item)),
            ).where((note) => note.id.isNotEmpty));
        }
      } catch (_) {
        // Keep a malformed value intact instead of silently erasing data.
      }
    }
    _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_notes.map((note) => note.toJson()).toList()),
    );
  }

  Future<void> _editNote({_PersonalNote? note}) async {
    final result = await showDialog<({String title, String body})>(
      context: context,
      builder: (_) => _NoteEditorDialog(note: note),
    );
    if (result == null || !mounted) return;

    final now = DateTime.now();
    setState(() {
      if (note == null) {
        _notes.insert(
          0,
          _PersonalNote(
            id: '${now.microsecondsSinceEpoch}',
            title: result.title,
            body: result.body,
            updatedAt: now,
          ),
        );
      } else {
        final index = _notes.indexWhere((item) => item.id == note.id);
        if (index >= 0) {
          _notes[index] = _PersonalNote(
            id: note.id,
            title: result.title,
            body: result.body,
            updatedAt: now,
          );
        }
      }
      _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    });
    await _persist();
  }

  Future<void> _deleteNote(_PersonalNote note) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: Text('«${note.title}» будет удалена с этого устройства.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    setState(() => _notes.removeWhere((item) => item.id == note.id));
    await _persist();
  }

  String _dateLabel(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои заметки'),
        actions: [
          IconButton(
            tooltip: 'Добавить заметку',
            onPressed: () => _editNote(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note_alt_outlined,
                            size: 52, color: scheme.primary),
                        const SizedBox(height: 12),
                        const Text(
                          'Пока нет заметок',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Записывай домашние задания, идеи и планы. '
                          'Заметки доступны офлайн.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _editNote(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Создать заметку'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                      child: Text(
                        'Заметки сохраняются только на этом устройстве. '
                        'Не записывай сюда пароли и другие секреты.',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                    for (final note in _notes)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                          title: Text(
                            note.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (note.body.isNotEmpty)
                                  Text(
                                    note.body,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 5),
                                Text(
                                  'Изменено: ${_dateLabel(note.updatedAt)}',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          onTap: () => _editNote(note: note),
                          trailing: SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: 'Редактировать заметку',
                                  onPressed: () => _editNote(note: note),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Удалить заметку',
                                  onPressed: () => _deleteNote(note),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
