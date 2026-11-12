import 'package:flutter/material.dart';

import 'dop_parser.dart';

/// Catalog for discovering and selecting additional-education programmes.
/// The actual programme data and form fields come from the school intranet.
class DopCatalogPage extends StatefulWidget {
  final Future<void> Function()? onEditStudent;
  final Future<void> Function()? onSelectionSubmitted;

  const DopCatalogPage({
    super.key,
    this.onEditStudent,
    this.onSelectionSubmitted,
  });

  @override
  State<DopCatalogPage> createState() => _DopCatalogPageState();
}

class _DopCatalogPageState extends State<DopCatalogPage> {
  final TextEditingController _searchController = TextEditingController();
  DopCatalogSession? _catalog;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String _query = '';
  String _direction = 'Все';
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _catalog?.close();
    _searchController.dispose();
    super.dispose();
  }

  String _key(DopSubgroup group) =>
      '${group.programId}:${group.subgroupId}:${group.selectionName}:${group.selectionValue}';

  Future<void> _loadCatalog() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    DopCatalogSession? opened;
    try {
      final loaded = await const DopParser().openCatalog();
      opened = loaded;
      if (!mounted) {
        loaded.close();
        return;
      }
      setState(() {
        _catalog?.close();
        _catalog = loaded;
        _selected
          ..clear()
          ..addAll(
            loaded.programs
                .expand((program) => program.subgroups)
                .where((group) => group.preselected)
                .map(_key),
          );
        _loading = false;
        _error = null;
        _direction = 'Все';
      });
    } catch (error) {
      opened?.close();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _catalog = null;
        _error = error.toString().replaceFirst('DopParserException: ', '');
      });
    }
  }

  Future<void> _editStudentAndRetry() async {
    await widget.onEditStudent?.call();
    if (!mounted) return;
    await _loadCatalog();
  }

  List<String> get _directions {
    final values = (_catalog?.programs ?? const <DopProgram>[])
        .map((program) => program.direction.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['Все', ...values];
  }

  List<DopProgram> get _visiblePrograms {
    final programs = _catalog?.programs ?? const <DopProgram>[];
    final needle = _query.trim().toLowerCase();
    return programs.where((program) {
      final matchesDirection =
          _direction == 'Все' || program.direction.trim() == _direction;
      if (!matchesDirection) return false;
      if (needle.isEmpty) return true;
      final searchable = [
        program.name,
        program.direction,
        program.classes,
        ...program.subgroups.map((group) => group.name),
        ...program.subgroups.map((group) => group.teacher),
      ].join(' ').toLowerCase();
      return searchable.contains(needle);
    }).toList();
  }

  int get _selectedCount => _selected.length;

  List<DopSubgroup> get _selectedGroups {
    final programs = _catalog?.programs ?? const <DopProgram>[];
    return programs
        .expand((program) => program.subgroups)
        .where((group) => _selected.contains(_key(group)))
        .toList();
  }

  Future<void> _submitSelection() async {
    final catalog = _catalog;
    if (catalog == null || _submitting) return;
    final selectedGroups = _selectedGroups;
    if (selectedGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала выбери хотя бы одну группу.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final message = await catalog.submit(selectedGroups);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
        ),
      );
      await widget.onSelectionSubmitted?.call();
      if (!mounted) return;
      // Keep the catalogue open so the student can review the response and
      // continue browsing. Refresh the server-side catalogue after submission.
      await _loadCatalog();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('DopParserException: ', ''),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _scheduleLabel(List<DopScheduleItem> schedule) {
    if (schedule.isEmpty) return 'Время уточняется';
    const days = <int, String>{
      1: 'Пн',
      2: 'Вт',
      3: 'Ср',
      4: 'Чт',
      5: 'Пт',
      6: 'Сб',
    };
    return schedule.map((slot) {
      final day = days[slot.day] ?? 'День ' + slot.day.toString();
      final lessons = slot.end > slot.start
          ? slot.start.toString() + '–' + slot.end.toString()
          : slot.start.toString();
      final room = slot.room.trim().isEmpty ? '' : ' • ' + slot.room.trim();
      return day + ' • уроки ' + lessons + room;
    }).join('\n');
  }

  Widget _buildUnavailable(ColorScheme scheme) {
    final needsProfile = (_error ?? '').toLowerCase().contains('профил') ||
        (_error ?? '').toLowerCase().contains('направлен') ||
        (_error ?? '').toLowerCase().contains('ученика');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                needsProfile ? Icons.person_search_rounded : Icons.cloud_off_rounded,
                size: 54,
                color: scheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                needsProfile
                    ? 'Сначала заполни профиль ученика'
                    : 'Не удалось загрузить каталог',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Проверь подключение к школьному intranet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (needsProfile && widget.onEditStudent != null)
                    FilledButton.icon(
                      onPressed: _editStudentAndRetry,
                      icon: const Icon(Icons.person_rounded),
                      label: const Text('Заполнить профиль'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _loadCatalog,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgramCard(DopProgram program, ColorScheme scheme) {
    final groups = program.subgroups;
    final canSubmit = _catalog?.canSubmit ?? false;
    final selectedInProgram = groups
        .where((group) => _selected.contains(_key(group)))
        .length;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(
            program.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (program.direction.isNotEmpty)
                  _CatalogBadge(
                    label: program.direction,
                    color: scheme.primary,
                  ),
                if (program.classes.isNotEmpty)
                  _CatalogBadge(
                    label: program.classes,
                    color: scheme.secondary,
                  ),
                if (program.hours > 0)
                  _CatalogBadge(
                    label: program.hours.toString() + ' ч.',
                    color: scheme.tertiary,
                  ),
                _CatalogBadge(
                  label: groups.isEmpty
                      ? 'Группы не распознаны'
                      : groups.length.toString() + ' групп',
                  color: scheme.outline,
                ),
                if (selectedInProgram > 0)
                  _CatalogBadge(
                    label: 'Выбрано: ' + selectedInProgram.toString(),
                    color: scheme.primary,
                  ),
              ],
            ),
          ),
          children: [
            if (program.startDate != null &&
                program.startDate!.trim().isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Начало: ' + program.startDate!,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'На странице нет распознанных карточек групп. Программа показана для ознакомления, но выбрать её пока нельзя.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              )
            else
              ...groups.map((group) {
                final selectable = canSubmit &&
                    group.selectionName.trim().isNotEmpty &&
                    group.selectionValue.trim().isNotEmpty;
                final checked = _selected.contains(_key(group));
                final details = <String>[
                  if (group.teacher.trim().isNotEmpty)
                    'Преподаватель: ' + group.teacher.trim(),
                  _scheduleLabel(group.schedule),
                  if (group.supplies != null &&
                      group.supplies!.trim().isNotEmpty)
                    'Что нужно: ' + group.supplies!.trim(),
                  if (group.hours > 0)
                    'Нагрузка: ' +
                        group.hours.toString() +
                        ' / ' +
                        group.limitHours.toString() +
                        ' ч.',
                ].join('\n');

                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: checked
                          ? scheme.primary.withValues(alpha: .55)
                          : scheme.outlineVariant,
                    ),
                  ),
                  child: CheckboxListTile(
                    value: checked,
                    onChanged: selectable
                        ? (value) {
                            setState(() {
                              if (value == true) {
                                _selected.add(_key(group));
                              } else {
                                _selected.remove(_key(group));
                              }
                            });
                          }
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    title: Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        selectable
                            ? details
                            : details +
                                '\nЗапись через форму сайта пока недоступна для этой группы.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final programs = _visiblePrograms;
    final canSubmit = _catalog?.canSubmit ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Каталог ДОПов'),
        actions: [
          IconButton(
            tooltip: 'Обновить каталог',
            onPressed: _loading ? null : _loadCatalog,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _catalog == null
              ? _buildUnavailable(scheme)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Дополнительное образование',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Выбери программу и подходящую группу. Сведения, направления и расписание загружаются с intranet.',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: InputDecoration(
                              hintText: 'Поиск программы, направления или педагога',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Очистить',
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _query = '');
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              filled: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 38,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _directions.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 7),
                              itemBuilder: (context, index) {
                                final value = _directions[index];
                                return ChoiceChip(
                                  label: Text(value),
                                  selected: value == _direction,
                                  onSelected: (_) =>
                                      setState(() => _direction = value),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  programs.length.toString() +
                                      ' программ • ' +
                                      _selectedCount.toString() +
                                      ' групп выбрано',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_catalog?.student.requiresProfile == true)
                                Text(
                                  'Профиль 10 класса учтён',
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: programs.isEmpty
                          ? Center(
                              child: Text(
                                'По этому фильтру программ нет',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                              itemCount: programs.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _buildProgramCard(programs[index], scheme),
                            ),
                    ),
                    if (canSubmit)
                      SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            border: Border(
                              top: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Выбрано групп: ' + _selectedCount.toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: _selectedCount == 0 || _submitting
                                    ? null
                                    : _submitSelection,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 17,
                                        height: 17,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: Text(
                                  _submitting
                                      ? 'Отправка…'
                                      : 'Отправить выбор',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Text(
                            'Каталог доступен для просмотра. Форма записи не найдена или не поддерживает безопасную отправку.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _CatalogBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CatalogBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == scheme.outline ? scheme.onSurfaceVariant : color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
