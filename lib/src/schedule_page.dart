part of '../main.dart';

class SchedulePage extends StatefulWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotes;
  const SchedulePage({super.key, required this.onMenu, required this.onNotes});
  @override State<SchedulePage> createState() => _SchedulePageState();
}
class _SchedulePageState extends State<SchedulePage> with WidgetsBindingObserver {
  int day = DateTime.now().weekday > 6 ? 1 : DateTime.now().weekday;
  List<ScheduleEntry> entries = [];
  String classId = '';
  int? wholeClassGroup;
  bool loading = true;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _appResumed = true;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    schoolLocalDataRevision.addListener(_reloadScheduleAfterAi);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    _syncClockTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) _now = DateTime.now();
    _syncClockTimer();
  }

  void _syncClockTimer() {
    final shouldTick = mounted && _appResumed && _tickerEnabled;
    if (shouldTick && _clockTimer == null) {
      _now = DateTime.now();
      _clockTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          if (mounted && _appResumed && _tickerEnabled) {
            setState(() => _now = DateTime.now());
          } else {
            _syncClockTimer();
          }
        },
      );
    } else if (!shouldTick && _clockTimer != null) {
      _clockTimer?.cancel();
      _clockTimer = null;
    }
  }
  void _reloadScheduleAfterAi() {
    if (!mounted) return;
    setState(() => loading = true);
    _load();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    schoolLocalDataRevision.removeListener(_reloadScheduleAfterAi);
    _clockTimer?.cancel();
    _clockTimer = null;
    super.dispose();
  }
  String? _breakCountdown(List<ScheduleEntry> dayEntries) => SchoolBellCountdown.describe(
    selectedDay: day,
    now: _now,
    lessons: dayEntries.map((entry) => (time: entry.time, subject: entry.subject)).toList(),
  );
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await SchoolScheduleCatalog.load();
    try {
      await SchoolScheduleCatalog.refreshOnline();
    } catch (_) {
      // The bundled or cached timetable remains usable without the server.
    }

    classId = p.getString('student_class_name') ?? '';
    wholeClassGroup = null;
    var needsWholeClassGroupSelection = false;
    final groups = <String, int>{};
    if (classId.isNotEmpty) {
      for (final subject in SchoolScheduleCatalog.splitSubjects(classId)) {
        groups[subject] = p.getInt(
              _studentScopedPreferenceKey(
                p,
                'student_group_${classId}_$subject',
              ),
            ) ??
            1;
      }

      if (SchoolScheduleCatalog.usesWholeClassSubgroup(classId)) {
        final storedGroup = p.getInt(
          _studentScopedPreferenceKey(p, 'student_class_group_8В'),
        );
        if (storedGroup == 1 || storedGroup == 2) {
          wholeClassGroup = storedGroup;
        } else {
          needsWholeClassGroupSelection = true;
        }
      }

      final mathNames = <int, List<String>>{};
      for (var d = 1; d <= 6; d++) {
        final dayNames = <String>[];
        for (var slot = 0; slot < 6; slot++) {
          dayNames.add(
            p.getString(
                  _studentScopedPreferenceKey(
                    p,
                    'math_subject_${classId}_${d}_$slot',
                  ),
                ) ??
                '',
          );
        }
        mathNames[d] = dayNames;
      }

      entries = needsWholeClassGroupSelection
          ? <ScheduleEntry>[]
          : SchoolScheduleCatalog.buildPersonal(
              classId,
              groups,
              mathNamesByDay: mathNames,
              wholeClassGroup: wholeClassGroup,
            );
    } else {
      entries = [];
    }

    if (needsWholeClassGroupSelection && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showStudentGroupSelection(context, classId);
        if (mounted) await _load();
      });
      return;
    }

    if (mounted) setState(() => loading = false);
    try {
      await LocalNotificationService().scheduleUpcomingLessons(
        entries: entries
            .map((e) => (
                  id: e.id,
                  day: e.day,
                  time: e.time,
                  subject: e.subject,
                  room: e.room,
                ))
            .toList(),
      );
    } catch (_) {
      // Notification permission/platform failures must not block the timetable.
    }

    if (classId.isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _chooseClass(required: true),
      );
    }
  }
  Future<void> _chooseClass({bool required = false}) async {
    final selected = await showDialog<String>(context: context, barrierDismissible: !required, builder: (_) => _StudentClassDialog(requiredChoice: required));
    if (selected == null || selected.isEmpty) return;
    final p = await SharedPreferences.getInstance(); await p.setString('student_class_name', selected); await p.setString('student_class_id', selected);
    if (!mounted) return; await showStudentGroupSelection(context, selected); await _load();
  }
  void _route(ScheduleEntry e) {
    if (e.room.isEmpty) return;
    final destination = SchoolData.tryRoom(e.room);
    if (destination == null) return;
    final sameDay = entries.where((x) => x.day == e.day).toList()..sort((a, b) => compareLessonTimes(a.time, b.time));
    final currentIndex = sameDay.indexWhere((x) => x.id == e.id);
    RoomInfo? previousRoom;
    if (currentIndex > 0) {
      for (var i = currentIndex - 1; i >= 0; i--) {
        final candidate = sameDay[i];
        if (candidate.room.isEmpty) continue;
        previousRoom = SchoolData.tryRoom(candidate.room);
        if (previousRoom != null) break;
      }
    }
    final route = RouteEngine.build(destination.id,
      startFloor: previousRoom?.floor ?? 1,
      startLocationId: previousRoom?.id,
    );
    if (route != null) Navigator.push(context, MaterialPageRoute(builder: (_) => RoutePage(room: destination, route: route)));
  }
  @override
  Widget build(BuildContext context) {
    final list = entries.where((e) => e.day == day).toList()..sort((a, b) => compareLessonTimes(a.time, b.time));
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final schedulePeriod = SchoolScheduleCatalog.periodForClass(classId);
    final splitSubjects = SchoolScheduleCatalog.splitSubjects(classId);
    final breakCountdown = _breakCountdown(list);
    const dayNames = ['', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Расписание'),
        actions: [
          if (width >= 460)
            IconButton(
              tooltip: 'Мои заметки',
              onPressed: widget.onNotes,
              icon: const Icon(Icons.note_alt_outlined),
            ),
          IconButton(tooltip: 'Выбрать класс', onPressed: () => _chooseClass(), icon: const Icon(Icons.school_rounded)),
          if (classId.isNotEmpty) ...[
            IconButton(
              tooltip: SchoolScheduleCatalog.usesWholeClassSubgroup(classId)
                  ? 'Выбрать подгруппу 8В'
                  : 'Группы по предметам',
              onPressed: () async {
                await showStudentGroupSelection(context, classId);
                await _load();
              },
              icon: const Icon(Icons.groups_rounded),
            ),
            IconButton(tooltip: 'Раздельная математика по дням', onPressed: () async { await showDialog<void>(context: context, builder: (_) => _MathByDayDialog(className: classId)); await _load(); }, icon: const Icon(Icons.functions_rounded)),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Padding(
            padding: EdgeInsets.fromLTRB(width < 600 ? 12 : 24, 12, width < 600 ? 12 : 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHigh]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.calendar_month_rounded, color: scheme.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        classId.isEmpty
                            ? 'Твоё расписание'
                            : 'Класс $classId${schedulePeriod.isEmpty ? '' : ' • $schedulePeriod'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        classId.isEmpty
                            ? 'Выбери класс, чтобы загрузить уроки'
                            : '${wholeClassGroup == null ? '' : 'Подгруппа 8В/$wholeClassGroup • '}${dayNames[day]} • ${list.length} ${list.length == 1 ? 'урок' : (list.length >= 2 && list.length <= 4 ? 'урока' : 'уроков')}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ])),
                    if (classId.isNotEmpty)
                      IconButton(
                        onPressed: () async {
                          await showStudentGroupSelection(context, classId);
                          await _load();
                        },
                        tooltip: SchoolScheduleCatalog.usesWholeClassSubgroup(classId)
                            ? 'Выбрать подгруппу 8В'
                            : 'Настроить группы',
                        icon: const Icon(Icons.tune_rounded),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Пн')),
                      ButtonSegment(value: 2, label: Text('Вт')),
                      ButtonSegment(value: 3, label: Text('Ср')),
                      ButtonSegment(value: 4, label: Text('Чт')),
                      ButtonSegment(value: 5, label: Text('Пт')),
                      ButtonSegment(value: 6, label: Text('Сб')),
                    ],
                    selected: {day},
                    onSelectionChanged: (value) => setState(() => day = value.first),
                  ),
                ),
                const SizedBox(height: 12),
                if (!loading && classId.isNotEmpty && breakCountdown != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.tertiary.withValues(alpha: .25)),
                    ),
                    child: Row(children: [
                      Icon(Icons.hourglass_bottom_rounded, color: scheme.onTertiaryContainer),
                      const SizedBox(width: 10),
                      Expanded(child: Text(breakCountdown, style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w800, fontSize: 13))),
                    ]),
                  ),
                ],
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : classId.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.school_outlined, size: 48, color: scheme.primary),
                                  const SizedBox(height: 12),
                                  const Text('Сначала выбери свой класс', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                                  const SizedBox(height: 6),
                                  Text('Приложение покажет предметы, группы и кабинеты именно для него.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(onPressed: () => _chooseClass(required: true), icon: const Icon(Icons.school_rounded), label: const Text('Выбрать класс')),
                                ]),
                              ),
                            )
                          : list.isEmpty
                              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.event_available_rounded, size: 44, color: scheme.onSurfaceVariant),
                                  const SizedBox(height: 10),
                                  const Text('В этот день уроков нет', style: TextStyle(fontWeight: FontWeight.w800)),
                                ]))
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  itemCount: list.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                                  itemBuilder: (context, index) {
                                    final e = list[index];
                                    final room = e.room.isEmpty ? null : SchoolData.tryRoom(e.room);
                                    final times = RegExp(r'\d{1,2}:\d{2}').allMatches(e.time).map((m) => m.group(0)!).toList();
                                    final startTime = times.isNotEmpty ? times.first : e.time;
                                    final endTime = times.length > 1 ? times[1] : '';
                                    return Card(
                                      clipBehavior: Clip.antiAlias,
                                      child: Padding(
                                        padding: const EdgeInsets.all(13),
                                        child: Row(children: [
                                          Container(
                                            width: 76,
                                            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                                            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(15)),
                                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                                              Text(startTime, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900, fontSize: 14)),
                                              if (endTime.isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                Text(endTime, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
                                              ],
                                            ]),
                                          ),
                                          const SizedBox(width: 13),
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(e.subject, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                            const SizedBox(height: 6),
                                            Wrap(spacing: 8, runSpacing: 5, children: [
                                              if (e.room.isNotEmpty)
                                                _ScheduleTag(icon: Icons.meeting_room_outlined, label: 'Каб. ${e.room}'),
                                              if (e.teacher.isNotEmpty)
                                                _ScheduleTag(icon: Icons.person_outline_rounded, label: e.teacher),
                                              if (splitSubjects.contains(e.subject) && e.group > 0)
                                                _ScheduleTag(icon: Icons.groups_2_outlined, label: 'Группа ${e.group}'),
                                            ]),
                                          ])),
                                          IconButton(
                                            onPressed: room == null ? null : () => _route(e),
                                            tooltip: room == null ? 'Маршрут для кабинета недоступен' : 'Как пройти',
                                            icon: const Icon(Icons.directions_rounded),
                                          ),
                                        ]),
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
class _ScheduleTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ScheduleTag({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
