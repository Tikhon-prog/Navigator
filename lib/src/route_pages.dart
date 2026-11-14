part of '../main.dart';

class RoutePage extends StatelessWidget {
  final RoomInfo room;
  final RouteResult route;
  const RoutePage({super.key, required this.room, required this.route});

  @override
  Widget build(BuildContext context) {
    final steps = RouteEngine.instructions(route);
    final floors = route.nodes.map((n) => n.floor).toSet().toList()..sort();
    final scheme = Theme.of(context).colorScheme;
    final origin = route.startLocationId == null ? 'Главный вход' : SchoolData.title(SchoolData.room(route.startLocationId!));
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(title: const Text('Маршрут')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: ListView(
            padding: EdgeInsets.fromLTRB(width < 600 ? 12 : 24, 12, width < 600 ? 12 : 24, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHigh]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(children: [
                  Container(width: 52, height: 52, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.directions_rounded, color: scheme.primary, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(SchoolData.title(room), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                    const SizedBox(height: 5),
                    Text('Откуда: $origin', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 3),
                    Text('Этаж назначения: ${room.floor} • ${floors.length} ${floors.length == 1 ? 'этаж' : 'этажа'} на маршруте', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ])),
                  Icon(Icons.flag_rounded, color: scheme.primary, size: 24),
                ]),
              ),
              const SizedBox(height: 22),
              Text('План маршрута', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final floor in floors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
                        child: Row(children: [
                          Tooltip(message: 'Этаж, по которому проходит маршрут', child: Icon(Icons.layers_rounded, color: scheme.primary)),
                          const SizedBox(width: 9),
                          Expanded(child: Text('$floor этаж', style: const TextStyle(fontWeight: FontWeight.w900))),
                          if (floor == room.floor)
                            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text('Назначение', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 11))),
                        ]),
                      ),
                      AspectRatio(
                        aspectRatio: 7016 / 4960,
                        child: Stack(children: [
                          Positioned.fill(child: Image.asset('assets/maps/floor$floor.webp', fit: BoxFit.contain)),
                          Positioned.fill(child: CustomPaint(painter: _RoutePainter(route.nodes, floor, const Color(0xFFFF2D95)))),
                        ]),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Пошаговые инструкции', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final item in steps.asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .11), borderRadius: BorderRadius.circular(14)), child: Center(child: Text('${item.key + 1}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900, fontSize: 15)))),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.value.text, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.35)),
                          const SizedBox(height: 5),
                          Text('${item.value.floor} этаж', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                        ])),
                        Icon(item.value.icon, color: scheme.primary),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<RouteNode> nodes;
  final int floor;
  final Color color;
  _RoutePainter(this.nodes, this.floor, this.color);

  @override
  void paint(Canvas c, Size s) {
    if (nodes.length < 2) return;
    final path = Path();
    var drawing = false;
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node.floor != floor) {
        drawing = false;
        continue;
      }
      final point = Offset(node.point.dx * s.width, node.point.dy * s.height);
      if (!drawing) {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      } else {
        final previous = nodes[i - 1];
        // Never bridge a floor transition: that would draw a false straight
        // line between two physically separate staircases on this floor.
        if (previous.floor == floor) {
          path.lineTo(point.dx, point.dy);
        } else {
          path.moveTo(point.dx, point.dy);
        }
      }
    }
    // White halo keeps the route readable over every department/map color.
    c.drawPath(path, Paint()
      ..color = Colors.white.withValues(alpha: .95)
      ..strokeWidth = 11
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    c.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.nodes != nodes || old.floor != floor || old.color != color;
}
class FullscreenMapPage extends StatefulWidget {
  final int floor;
  final String? selectedRoom;
  final String? routeRoom;
  final int startFloor;
  final String? startLocationId;

  const FullscreenMapPage({
    super.key,
    required this.floor,
    required this.selectedRoom,
    required this.routeRoom,
    required this.startFloor,
    required this.startLocationId,
  });

  @override
  State<FullscreenMapPage> createState() => _FullscreenMapPageState();
}

class _FullscreenMapPageState extends State<FullscreenMapPage> {
  late int floor = widget.floor;
  final TransformationController _zoom = TransformationController();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _changeZoom(double delta, Size size) {
    final current = _zoom.value.getMaxScaleOnAxis();
    final next = (current + delta).clamp(.6, 6.0).toDouble();
    _zoom.value = Matrix4.identity()
      ..translateByDouble(
        size.width * (1 - next) / 2,
        size.height * (1 - next) / 2,
        0,
        1,
      )
      ..scaleByDouble(next, next, next, 1);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedRoom == null ? null : SchoolData.tryRoom(widget.selectedRoom!);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('$floor этаж • полноэкранная карта'),
        actions: [
          if (selected != null && selected.floor == floor)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(SchoolData.title(selected), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 этаж')),
                      ButtonSegment(value: 2, label: Text('2 этаж')),
                      ButtonSegment(value: 3, label: Text('3 этаж')),
                    ],
                    selected: {floor},
                    onSelectionChanged: (value) {
                      setState(() {
                        floor = value.first;
                        _zoom.value = Matrix4.identity();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Сбросить масштаб',
                  onPressed: () => setState(() => _zoom.value = Matrix4.identity()),
                  icon: const Icon(Icons.fit_screen_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: _zoom,
                      minScale: .6,
                      maxScale: 6,
                      boundaryMargin: const EdgeInsets.all(100),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1600),
                          child: AspectRatio(
                            aspectRatio: 7016 / 4960,
                            child: Stack(
                              children: [
                                Positioned.fill(child: Image.asset('assets/maps/floor$floor.webp', fit: BoxFit.contain)),
                                if (selected != null && selected.floor == floor)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _PointPainter(SchoolData.point(selected), scheme.primary),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'map_zoom_in',
                          tooltip: 'Увеличить',
                          onPressed: () => _changeZoom(.35, Size(constraints.maxWidth, constraints.maxHeight)),
                          child: const Icon(Icons.add_rounded),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'map_zoom_out',
                          tooltip: 'Уменьшить',
                          onPressed: () => _changeZoom(-.35, Size(constraints.maxWidth, constraints.maxHeight)),
                          child: const Icon(Icons.remove_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
