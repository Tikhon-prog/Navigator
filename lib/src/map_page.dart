part of '../main.dart';

class _StartChoice {
  final int floor;
  final String? id;
  const _StartChoice({required this.floor, required this.id});
}

class _StartDialog extends StatefulWidget {
  final int floor;
  final String? id;
  const _StartDialog({required this.floor, required this.id});
  @override State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  late int floor = widget.floor;
  late String choice = widget.id ?? '__entrance__';
  @override Widget build(BuildContext context) {
    final rooms = SchoolData.locations.where((r) => r.floor == floor).toList();
    final values = <String>[
      if (floor == 1) '__entrance__',
      ...rooms.map((r) => r.id),
    ];
    if (values.isNotEmpty && !values.contains(choice)) choice = values.first;
    return AlertDialog(
      title: const Text('Начало маршрута'),
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<int>(segments: const [ButtonSegment(value:1,label:Text('1 этаж')),ButtonSegment(value:2,label:Text('2 этаж')),ButtonSegment(value:3,label:Text('3 этаж'))], selected:{floor}, onSelectionChanged:(v){setState((){floor=v.first;choice='__entrance__';});}),
        const SizedBox(height: 14),
        if (values.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('На этом этаже нет помещений'))
        else
          DropdownButtonFormField<String>(key: ValueKey(floor), initialValue: choice, isExpanded: true, decoration: const InputDecoration(labelText:'Точка старта'), items: [
          if (floor == 1) const DropdownMenuItem(value:'__entrance__',child:Text('Главный вход')),
          ...rooms.map((r)=>DropdownMenuItem(value:r.id,child:Text(SchoolData.isPlace(r) ? SchoolData.title(r) : '${r.id} — ${r.name}'))),
        ], onChanged:(v)=>setState(()=>choice=v??values.first)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Отмена')),FilledButton(onPressed:values.isEmpty?null:()=>Navigator.pop(context,_StartChoice(floor:floor,id:choice=='__entrance__'?null:choice)),child:const Text('Сохранить'))],
    );
  }
}
class MapPage extends StatefulWidget {
  final String? initialRoom; final VoidCallback onMenu;
  const MapPage({super.key,this.initialRoom,required this.onMenu});
  @override State<MapPage> createState()=>_MapPageState();
}
class _MapPageState extends State<MapPage>{
  static const _favoritesKey = 'pokolenie_favorite_locations_v1';
  int floor=1;
  String query='';
  String? selected;
  int startFloor=1;
  String? startId;
  SchoolLocationCategory? activeCategory;
  bool showFavoritesOnly = false;
  Set<String> favoriteIds = {};
  final search=TextEditingController();
  @override void initState(){
    super.initState();
    // Same guard as didUpdateWidget: a stale room id must not crash the map.
    final initial = widget.initialRoom == null ? null : SchoolData.tryRoom(widget.initialRoom!);
    selected = initial?.id;
    if (initial != null) floor = initial.floor;
    schoolLocalDataRevision.addListener(_reloadPreferencesAfterAi);
    _load();
  }
  void _reloadPreferencesAfterAi() {
    if (mounted) _load();
  }
  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRoom != oldWidget.initialRoom && widget.initialRoom != null) {
      final room = SchoolData.tryRoom(widget.initialRoom!);
      if (room != null) {
        selected = room.id;
        floor = room.floor;
      }
    }
  }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    startFloor = prefs.getInt('map_start_floor') ?? 1;
    // Drop a saved start point that no longer exists in the current map data.
    final savedStart = prefs.getString('map_start_location');
    startId = savedStart != null && SchoolData.tryRoom(savedStart) != null ? savedStart : null;
    favoriteIds = (prefs.getStringList(_favoritesKey) ?? const <String>[]).toSet();
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite(RoomInfo room) async {
    final next = Set<String>.from(favoriteIds);
    if (!next.add(room.id)) next.remove(room.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, next.toList()..sort());
    if (mounted) setState(() => favoriteIds = next);
  }

  void _selectCategory(SchoolLocationCategory? category, {bool favorites = false}) {
    setState(() {
      activeCategory = category;
      showFavoritesOnly = favorites;
    });
  }

  int _countForCategory(SchoolLocationCategory? category) {
    return SchoolData.locationsOnFloor(floor)
        .where((room) => category == null || SchoolData.category(room) == category)
        .length;
  }

  int get _favoriteCountOnFloor => SchoolData.locationsOnFloor(floor)
      .where((room) => favoriteIds.contains(room.id))
      .length;
  @override void dispose(){
    schoolLocalDataRevision.removeListener(_reloadPreferencesAfterAi);
    search.dispose();
    super.dispose();
  }
  List<RoomInfo> get rooms => SchoolData.locationsOnFloor(floor).where((room) {
    final normalizedQuery = query.trim().toLowerCase();
    final matchesQuery = normalizedQuery.isEmpty ||
        room.id.toLowerCase().contains(normalizedQuery) ||
        SchoolData.title(room).toLowerCase().contains(normalizedQuery);
    final matchesCategory = activeCategory == null ||
        SchoolData.category(room) == activeCategory;
    final matchesFavorites = !showFavoritesOnly || favoriteIds.contains(room.id);
    return matchesQuery && matchesCategory && matchesFavorites;
  }).toList();
  Future<void> _start() async {
    final choice = await showDialog<_StartChoice>(
      context: context,
      builder: (_) => _StartDialog(floor: startFloor, id: startId),
    );
    if (choice == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await prefs.setInt('map_start_floor', choice.floor);
    if (choice.id == null) {
      await prefs.remove('map_start_location');
    } else {
      await prefs.setString('map_start_location', choice.id!);
    }

    if (!mounted) return;
    setState(() {
      startFloor = choice.floor;
      startId = choice.id;
    });
  }
  void _open(RoomInfo room) {
    setState(() => selected = room.id);
    final route = RouteEngine.build(
      room.id,
      startFloor: startFloor,
      startLocationId: startId,
    );
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Маршрут для этой точки недоступен.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePage(room: room, route: route),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wideScreen = MediaQuery.sizeOf(context).width >= 900;
    Widget locationsPanel() => Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant.withValues(alpha: .8))),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: scheme.surfaceContainerHigh,
            child: ListTile(
              leading: Icon(Icons.my_location_rounded, color: scheme.primary),
              title: const Text('Откуда идём?', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(startId == null ? 'Главный вход' : SchoolData.title(SchoolData.room(startId!))),
              trailing: const Icon(Icons.tune_rounded),
              onTap: _start,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 17, 5, 9),
            child: Row(children: [
              Expanded(child: Text('Этаж $floor', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              Text('${rooms.length} мест', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (rooms.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(Icons.search_off_rounded, size: 34, color: scheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(
                  showFavoritesOnly ? 'Пока нет избранных мест' : 'Ничего не найдено',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  showFavoritesOnly
                      ? 'Отметь кабинет звёздочкой, чтобы быстро находить его здесь.'
                      : 'Попробуй другой запрос или категорию.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ]),
            )
          else
            ...rooms.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Card(
                color: selected == r.id ? scheme.primaryContainer.withValues(alpha: .55) : scheme.surfaceContainer,
                child: ListTile(
                  dense: true,
                  leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)), child: Icon(SchoolData.isPlace(r) ? Icons.place_rounded : Icons.meeting_room_rounded, color: scheme.primary)),
                  title: Text(SchoolData.title(r), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text(
                    '${SchoolData.category(r).label} · этаж ${r.floor}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: favoriteIds.contains(r.id)
                            ? 'Убрать из избранного'
                            : 'Добавить в избранное',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _toggleFavorite(r),
                        icon: Icon(
                          favoriteIds.contains(r.id)
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: favoriteIds.contains(r.id)
                              ? scheme.tertiary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                    ],
                  ),
                  onTap: () => _open(r),
                ),
              ),
            )),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Карта школы'),
        actions: [
          IconButton(onPressed: _start, tooltip: 'Начало маршрута', icon: const Icon(Icons.my_location_rounded)),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenMapPage(floor: floor, selectedRoom: selected, routeRoom: null, startFloor: startFloor, startLocationId: startId))), tooltip: 'Полноэкранная карта', icon: const Icon(Icons.fullscreen_rounded)),
          IconButton(onPressed: () => setState(() { query = ''; search.clear(); }), tooltip: 'Очистить поиск', icon: const Icon(Icons.clear_all_rounded)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Expanded(child: TextField(controller: search, onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Кабинет, бассейн, библиотека…'))),
                const SizedBox(width: 10),
                SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 3, label: Text('3'))],
                  selected: {floor},
                  onSelectionChanged: (v) => setState(() => floor = v.first),
                ),
              ]),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text('Все (${_countForCategory(null)})'),
                      selected: activeCategory == null && !showFavoritesOnly,
                      onSelected: (_) => _selectCategory(null),
                    ),
                  ),
                  for (final category in SchoolLocationCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        avatar: Icon(category.icon, size: 17),
                        label: Text('${category.label} (${_countForCategory(category)})'),
                        selected: activeCategory == category && !showFavoritesOnly,
                        onSelected: (_) => _selectCategory(category),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: FilterChip(
                      avatar: const Icon(Icons.star_rounded, size: 17),
                      label: Text('Избранное ($_favoriteCountOnFloor)'),
                      selected: showFavoritesOnly,
                      onSelected: (value) => _selectCategory(null, favorites: value),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: wideScreen
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(children: [
                        Expanded(flex: 3, child: _MapImage(floor: floor, selected: selected)),
                        const SizedBox(width: 14),
                        SizedBox(width: 350, child: locationsPanel()),
                      ]),
                    )
                  : Column(children: [
                      SizedBox(height: math.min(320.0, constraints.maxHeight * .40), child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: _MapImage(floor: floor, selected: selected))),
                      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: locationsPanel())),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

}
class _MapImage extends StatelessWidget{final int floor;final String? selected;const _MapImage({required this.floor,required this.selected});@override Widget build(BuildContext context)=>Card(clipBehavior:Clip.antiAlias,child:InteractiveViewer(minScale:.7,maxScale:4,child:AspectRatio(aspectRatio:7016/4960,child:Stack(children:[Positioned.fill(child:Image.asset('assets/maps/floor$floor.webp',fit:BoxFit.contain)),if(selected!=null)Positioned.fill(child:CustomPaint(painter:_PointPainter(SchoolData.point(SchoolData.room(selected!)),Theme.of(context).colorScheme.primary)))]))));}
class _PointPainter extends CustomPainter{final Offset p;final Color color;_PointPainter(this.p,this.color);@override void paint(Canvas c,Size s){final o=Offset(p.dx*s.width,p.dy*s.height);c.drawCircle(o,9,Paint()..color=color);c.drawCircle(o,17,Paint()..color=color.withValues(alpha:.22));}@override bool shouldRepaint(covariant _PointPainter o)=>o.p!=p||o.color!=color;}
class _MathByDayDialog extends StatefulWidget {
  final String className;
  const _MathByDayDialog({required this.className});
  @override State<_MathByDayDialog> createState() => _MathByDayDialogState();
}
class _MathByDayDialogState extends State<_MathByDayDialog> {
  static const days = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];
  static const subjects = ['', 'Алгебра', 'Геометрия', 'Вероятность и статистика'];
  final selected = <String, String>{};
  @override void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        for (var d = 1; d <= 6; d++) {
          for (var slot = 0; slot < 6; slot++) {
            selected['$d|$slot'] = p.getString(_studentScopedPreferenceKey(p, 'math_subject_${widget.className}_${d}_$slot')) ?? '';
          }
        }
      });
    });
  }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Раздельная математика'),
    content: SizedBox(width: MediaQuery.sizeOf(context).width * .82, child: ListView(shrinkWrap: true, children: [
      const Text('Настрой названия математических уроков отдельно для каждого дня. Если уроков несколько, они идут по времени: первый, второй и далее.'),
      const SizedBox(height: 10),
      for (var d = 1; d <= 6; d++) ...[
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(days[d - 1], style: const TextStyle(fontWeight: FontWeight.w800))),
        for (var slot = 0; slot < SchoolScheduleCatalog.mathLessonCount(widget.className, d); slot++)
          DropdownButtonFormField<String>(
            // initialValue is read once; re-key so values loaded from prefs after the
            // first frame are actually shown.
            key: ValueKey('$d|$slot|${selected['$d|$slot']}'),
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Математика — урок ${slot + 1}', isDense: true),
            initialValue: subjects.contains(selected['$d|$slot'] ?? '') ? selected['$d|$slot'] : '',
            items: subjects.map((x) => DropdownMenuItem(value: x, child: Text(x.isEmpty ? 'Не переименовывать' : x))).toList(),
            onChanged: (v) => setState(() => selected['$d|$slot'] = v ?? ''),
          ),
      ],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () async {
        final p = await SharedPreferences.getInstance();
        for (var d = 1; d <= 6; d++) {
          for (var slot = 0; slot < 6; slot++) {
            await p.setString(_studentScopedPreferenceKey(p, 'math_subject_${widget.className}_${d}_$slot'), selected['$d|$slot'] ?? '');
          }
        }
        if (context.mounted) Navigator.pop(context);
      }, child: const Text('Сохранить')),
    ],
  );
}
