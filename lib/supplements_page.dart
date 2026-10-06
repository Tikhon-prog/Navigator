import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

class Supplement {
  final String id;
  final String title;
  final String teacher;
  final String room;
  final String place;
  final String groupName;
  final String description;
  final int weekday;
  final String start;
  final String end;

  const Supplement({
    required this.id,
    required this.title,
    required this.weekday,
    required this.start,
    required this.end,
    required this.teacher,
    required this.room,
    required this.place,
    required this.groupName,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'weekday': weekday,
        'start': start,
        'end': end,
        'teacher': teacher,
        'room': room,
        'place': place,
        'group': groupName,
        'description': description,
      };

  factory Supplement.fromJson(Map<String, dynamic> json) => Supplement(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        weekday: (json['weekday'] as num?)?.toInt() ?? 1,
        start: '${json['start'] ?? ''}',
        end: '${json['end'] ?? ''}',
        teacher: '${json['teacher'] ?? ''}',
        room: '${json['room'] ?? ''}',
        place: '${json['place'] ?? ''}',
        groupName: '${json['group'] ?? ''}',
        description: '${json['description'] ?? ''}',
      );
}

class SupplementsPage extends StatefulWidget {
  final VoidCallback onMenu;
  const SupplementsPage({super.key, required this.onMenu});

  @override
  State<SupplementsPage> createState() => _SupplementsPageState();
}

class _SupplementsPageState extends State<SupplementsPage> {
  int day = DateTime.now().weekday.clamp(1, 6);
  List<Supplement> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('supplements_local');
    if (raw != null) {
      try {
        items = (jsonDecode(raw) as List)
            .map((e) => Supplement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        items = [];
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'supplements_local',
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = items.where((e) => e.weekday == day).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('ДОПы', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Добавить ДОП',
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 1, label: Text('Пн')),
                          ButtonSegment(value: 2, label: Text('Вт')),
                          ButtonSegment(value: 3, label: Text('Ср')),
                          ButtonSegment(value: 4, label: Text('Чт')),
                          ButtonSegment(value: 5, label: Text('Пт')),
                          ButtonSegment(value: 6, label: Text('Сб')),
                        ],
                        selected: {day},
                        onSelectionChanged: (value) {
                          setState(() => day = value.first);
                        },
                      ),
                    ),
                    Expanded(
                      child: current.isEmpty
                          ? const Center(child: Text('На этот день ДОПов нет'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(18),
                              itemCount: current.length,
                              itemBuilder: (context, index) => _card(current[index]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _card(Supplement supplement) {
    final details = <String>[
      if (supplement.start.isNotEmpty)
        '${supplement.start}${supplement.end.isNotEmpty ? '–${supplement.end}' : ''}',
      if (supplement.teacher.isNotEmpty) supplement.teacher,
      if (supplement.room.isNotEmpty) 'каб. ${supplement.room}',
      if (supplement.place.isNotEmpty) supplement.place,
      if (supplement.groupName.isNotEmpty) supplement.groupName,
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(
          child: Text(supplement.start.isEmpty ? '•' : supplement.start.split(':').first),
        ),
        title: Text(
          supplement.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          details.isEmpty ? supplement.description : details,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _edit(supplement);
            if (value == 'delete') _delete(supplement);
            if (value == 'route' && supplement.room.isNotEmpty) {
              final route = RouteEngine.build(supplement.room);
              if (route != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoutePage(
                      room: SchoolData.room(supplement.room),
                      route: route,
                    ),
                  ),
                );
              }
            }
          },
          itemBuilder: (_) => [
            if (supplement.room.isNotEmpty)
              const PopupMenuItem(value: 'route', child: Text('Как пройти')),
            const PopupMenuItem(value: 'edit', child: Text('Изменить')),
            const PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final result = await showDialog<Supplement>(
      context: context,
      builder: (_) => const _SupplementEditor(),
    );
    if (result != null) {
      setState(() => items.add(result));
      await _save();
    }
  }

  Future<void> _edit(Supplement old) async {
    final result = await showDialog<Supplement>(
      context: context,
      builder: (_) => _SupplementEditor(initial: old),
    );
    if (result != null) {
      final index = items.indexWhere((e) => e.id == old.id);
      if (index >= 0) {
        setState(() => items[index] = result);
        await _save();
      }
    }
  }

  Future<void> _delete(Supplement supplement) async {
    setState(() => items.removeWhere((e) => e.id == supplement.id));
    await _save();
  }
}

class _SupplementEditor extends StatefulWidget {
  final Supplement? initial;

  const _SupplementEditor({this.initial});

  @override
  State<_SupplementEditor> createState() => _SupplementEditorState();
}

class _SupplementEditorState extends State<_SupplementEditor> {
  late int day;
  late final TextEditingController title;
  late final TextEditingController start;
  late final TextEditingController end;
  late final TextEditingController teacher;
  late final TextEditingController room;
  late final TextEditingController place;
  late final TextEditingController group;
  late final TextEditingController description;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    day = item?.weekday ?? DateTime.now().weekday.clamp(1, 6);
    title = TextEditingController(text: item?.title ?? '');
    start = TextEditingController(text: item?.start ?? '');
    end = TextEditingController(text: item?.end ?? '');
    teacher = TextEditingController(text: item?.teacher ?? '');
    room = TextEditingController(text: item?.room ?? '');
    place = TextEditingController(text: item?.place ?? '');
    group = TextEditingController(text: item?.groupName ?? '');
    description = TextEditingController(text: item?.description ?? '');
  }

  @override
  void dispose() {
    for (final controller in [title, start, end, teacher, room, place, group, description]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Новый ДОП' : 'Изменить ДОП'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            children: [
              DropdownButtonFormField<int>(
                initialValue: day,
                decoration: const InputDecoration(labelText: 'День'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Понедельник')),
                  DropdownMenuItem(value: 2, child: Text('Вторник')),
                  DropdownMenuItem(value: 3, child: Text('Среда')),
                  DropdownMenuItem(value: 4, child: Text('Четверг')),
                  DropdownMenuItem(value: 5, child: Text('Пятница')),
                  DropdownMenuItem(value: 6, child: Text('Суббота')),
                ],
                onChanged: (value) => setState(() => day = value ?? day),
              ),
              const SizedBox(height: 8),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Название')),
              TextField(controller: start, decoration: const InputDecoration(labelText: 'Начало', hintText: '16:00')),
              TextField(controller: end, decoration: const InputDecoration(labelText: 'Конец', hintText: '17:30')),
              TextField(controller: teacher, decoration: const InputDecoration(labelText: 'Учитель')),
              TextField(controller: room, decoration: const InputDecoration(labelText: 'Кабинет')),
              TextField(controller: place, decoration: const InputDecoration(labelText: 'Место / зона')),
              TextField(controller: group, decoration: const InputDecoration(labelText: 'Группа')),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              Supplement(
                id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                title: title.text.trim(),
                weekday: day,
                start: start.text.trim(),
                end: end.text.trim(),
                teacher: teacher.text.trim(),
                room: room.text.trim(),
                place: place.text.trim(),
                groupName: group.text.trim(),
                description: description.text.trim(),
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
