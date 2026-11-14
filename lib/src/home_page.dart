part of '../main.dart';

class HomePage extends StatelessWidget {
  final String userName;
  final AppThemeType theme;
  final VoidCallback onMenu, onMap, onSchedule, onDop, onAnnouncements, onAiChat;
  const HomePage({super.key, required this.userName, required this.theme, required this.onMenu, required this.onMap, required this.onSchedule, required this.onDop, required this.onAnnouncements, required this.onAiChat});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.gradient(theme);
    final textColor = theme == AppThemeType.darkBlue ? Colors.white : const Color(0xFF142238);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 980 ? 3 : width >= 640 ? 2 : 1;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Поколение'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: EdgeInsets.fromLTRB(width < 600 ? 16 : 28, 16, width < 600 ? 16 : 28, 32),
            children: [
              Container(
                padding: EdgeInsets.all(width < 600 ? 22 : 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: colors.first.withValues(alpha: .18), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(color: textColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
                    child: Text('ШКОЛА «ПОКОЛЕНИЕ»', style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                  ),
                  const SizedBox(height: 18),
                  Text(userName.trim().isEmpty ? 'Всё для школы\nв одном месте' : 'Привет, $userName!', style: TextStyle(color: textColor, fontSize: width < 600 ? 30 : 38, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  const SizedBox(height: 12),
                  Text('Карта здания, расписание уроков и дополнительные занятия — всё в одном месте.', style: TextStyle(color: textColor.withValues(alpha: .9), fontSize: 15, height: 1.45)),
                  const SizedBox(height: 22),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    _HeroButton('Открыть карту', Icons.explore_rounded, onMap, foreground: textColor),
                    _HeroButton('Моё расписание', Icons.calendar_month_rounded, onSchedule, foreground: textColor),
                    _HeroButton('Спросить ИИ', Icons.auto_awesome_rounded, onAiChat, foreground: textColor),
                  ]),
                ]),
              ),
              const SizedBox(height: 28),
              Row(children: [
                Expanded(child: Text('Быстрый доступ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.4))),
                Text('5 разделов', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: columns == 1 ? 3.0 : 1.55,
                children: [
                  _DashboardCard(icon: Icons.map_rounded, title: 'Карта школы', subtitle: 'Найди кабинет и построй маршрут', accent: const Color(0xFF3284F5), onTap: onMap),
                  _DashboardCard(icon: Icons.calendar_month_rounded, title: 'Расписание', subtitle: 'Уроки, группы и кабинеты', accent: const Color(0xFF13A88A), onTap: onSchedule),
                  _DashboardCard(icon: Icons.auto_awesome_rounded, title: 'Дополнительные занятия', subtitle: 'ДОПы, время и преподаватели', accent: const Color(0xFF9667E8), onTap: onDop),
                  _DashboardCard(icon: Icons.campaign_rounded, title: 'Объявления и оповещения', subtitle: 'Новости школы и важные сообщения', accent: const Color(0xFFE58B35), onTap: onAnnouncements),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final Color foreground;
  const _HeroButton(this.text, this.icon, this.onTap, {required this.foreground});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    icon: Icon(icon),
    label: Text(text),
    style: FilledButton.styleFrom(backgroundColor: foreground.withValues(alpha: .13), foregroundColor: foreground, side: BorderSide(color: foreground.withValues(alpha: .24))),
  );
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  const _DashboardCard({required this.icon, required this.title, required this.subtitle, required this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: accent, size: 26)),
            const SizedBox(width: 14),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 5),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.3)),
            ])),
            const SizedBox(width: 6),
            Icon(Icons.arrow_outward_rounded, size: 18, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
