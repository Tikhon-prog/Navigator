part of '../main.dart';

class _StudentClassDialog extends StatefulWidget {
  final bool requiredChoice;
  const _StudentClassDialog({this.requiredChoice = false});
  @override State<_StudentClassDialog> createState() => _StudentClassDialogState();
}
class _StudentClassDialogState extends State<_StudentClassDialog> {
  String? grade;
  @override Widget build(BuildContext context) {
    final grades = SchoolScheduleCatalog.grades();
    final classes = grade == null ? const <String>[] : SchoolScheduleCatalog.classesForGrade(grade!);
    return AlertDialog(title: const Text('Выбери класс'), content: SizedBox(width: 430, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Расписание встроено в приложение.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: grade, decoration: const InputDecoration(labelText: 'Параллель'), items: grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(), onChanged: (v) => setState(() => grade = v)),
      if (classes.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: classes.map((c) => ActionChip(label: Text(c), onPressed: () => Navigator.pop(context, c))).toList())],
    ])), actions: widget.requiredChoice ? null : [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена'))]);
  }
}
String _studentScopedPreferenceKey(SharedPreferences prefs, String key) {
  var userId = '';
  final raw = prefs.getString('school_user_v1');
  if (raw != null) {
    try {
      final account = jsonDecode(raw);
      if (account is Map && account['id'] != null) {
        userId = account['id'].toString().trim();
      }
    } catch (error) { debugPrint('student_dialogs: ${error.runtimeType}'); }
  }
  // Keeps the old keys for offline-only installs, while separating group
  // choices for signed-in students sharing the same device.
  return studentProfilePreferenceKey(key, userId: userId);
}

Future<void> showStudentGroupSelection(BuildContext context, String className) async {
  await SchoolScheduleCatalog.load();
  if (!context.mounted) return;
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;

  final subjects = SchoolScheduleCatalog.splitSubjects(className).toList()..sort();
  if (subjects.isEmpty) return;
  final values = <String, int>{
    for (final subject in subjects)
      subject: prefs.getInt(
            _studentScopedPreferenceKey(prefs, 'student_group_${className}_$subject'),
          ) ??
          1,
  };
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _StudentGroupsDialog(
      className: className,
      subjects: subjects,
      values: values,
    ),
  );
}

class _StudentGroupsDialog extends StatefulWidget {
  final String className; final List<String> subjects; final Map<String, int> values;
  const _StudentGroupsDialog({required this.className, required this.subjects, required this.values});
  @override State<_StudentGroupsDialog> createState() => _StudentGroupsDialogState();
}
class _StudentGroupsDialogState extends State<_StudentGroupsDialog> {
  late final values = Map<String, int>.of(widget.values);
  late final available = SchoolScheduleCatalog.subjectGroups(widget.className);
  @override Widget build(BuildContext context) => AlertDialog(
    title: Text('Группы • ${widget.className}'),
    content: SizedBox(width: MediaQuery.sizeOf(context).width * .82, child: ListView(shrinkWrap: true, children: widget.subjects.map((s) {
      final known = available[s];
      final groups = (known == null || known.isEmpty ? <int>{1} : known).toList()..sort();
      String groupLabel(int group) =>
          SchoolScheduleCatalog.subgroupLabel(widget.className, s, group);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(SchoolScheduleCatalog.choiceTitle(s), softWrap: true, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Подгруппа / преподаватель',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              initialValue: groups.contains(values[s]) ? values[s] : groups.first,
              items: groups.map((g) => DropdownMenuItem(
                value: g,
                child: Text(groupLabel(g), maxLines: 1, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (value) { if (value != null) setState(() => values[s] = value); },
            ),
          ],
        ),
      );
    }).toList())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          for (final entry in values.entries) {
            await prefs.setInt(
              _studentScopedPreferenceKey(
                prefs,
                'student_group_${widget.className}_${entry.key}',
              ),
              entry.value,
            );
          }
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Сохранить'),
      ),
    ],
  );
}
