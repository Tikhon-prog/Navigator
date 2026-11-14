part of '../main.dart';

class SettingsPage extends StatelessWidget {
  final AppThemeType theme;
  final String userName;
  final ValueChanged<AppThemeType> onThemeChanged;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onMenu;
  const SettingsPage({super.key, required this.theme, required this.userName, required this.onThemeChanged, required this.onNameChanged, required this.onMenu});

  Future<void> _openAdmin(BuildContext context) async {
    final account = await showDialog<AdminAccount>(context: context, builder: (_) => const AdminLoginDialog());
    if (account == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPanelPage(account: account)));
  }

  Future<void> _serverAdminLogin(BuildContext context, String baseUrl) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _ServerAdminLoginDialog(),
    );
    if (result == null) return;
    try {
      await SchoolAccountService().signInAsServerAdmin(
        baseUrl, username: result['username']!, password: result['password']!,
      );
      unawaited(desktop_polling.startDesktopNotificationPolling());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Технический вход выполнен.')));
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
      }
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), duration: const Duration(seconds: 6)),
      );
    }
  }

  Future<void> _schoolAccount(BuildContext context) async {
    final service = SchoolAccountService();
    final current = await service.currentUser();
    if (!context.mounted) return;
    if (current != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Школьная учётная запись'),
          content: Text('Вход выполнен: ${current['display_name'] ?? current['username'] ?? 'учётная запись'}\nРоль: ${current['role'] ?? 'не указана'}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'close'), child: const Text('Закрыть')),
            OutlinedButton(onPressed: () => Navigator.pop(dialogContext, 'signout'), child: const Text('Выйти')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'portal'),
              child: Text(current['role'] == 'student' ? 'Мои оповещения' : 'Открыть кабинет'),
            ),
          ],
        ),
      );
      if (action == 'signout') {
        try {
          await service.signOut();
          await desktop_polling.stopDesktopNotificationPolling();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы вышли из школьной учётной записи.')));
        } catch (error) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось выйти: ${error.toString().replaceFirst('Exception: ', '')}')));
        }
      } else if (action == 'portal' && context.mounted) {
        if (current['role'] == 'student') {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
        } else {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
        }
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final enabled = prefs.getBool('navigator_api_enabled') ?? false;
    final baseUrl = (prefs.getString('navigator_api_url') ?? '').trim();
    if (!enabled || baseUrl.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала настрой адрес API в «Кабинет школы → Сервер».')));
      return;
    }
    final loginMethod = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Вход в Поколение'),
        content: const Text('Выбери школьный вход. Технический вход нужен только администратору для первоначальной настройки или восстановления доступа.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('Отмена')),
          OutlinedButton(onPressed: () => Navigator.pop(dialogContext, 'admin'), child: const Text('Технический вход')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'sso'), child: const Text('Школьный SSO')),
        ],
      ),
    );
    if (!context.mounted || loginMethod == null || loginMethod == 'cancel') return;
    if (loginMethod == 'admin') {
      await _serverAdminLogin(context, baseUrl);
      return;
    }
    try {
      final result = await service.signInWithSchoolAccount(baseUrl);
      final user = Map<String, dynamic>.from(result['user'] as Map);
      unawaited(desktop_polling.startDesktopNotificationPolling());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Вход выполнен: ${user['display_name'] ?? user['username'] ?? 'учётная запись'}.${result['push_registered'] == true ? ' Уведомления подключены.' : ' Push-уведомления пока не настроены.'}'),
          duration: const Duration(seconds: 5),
        ));
        if (user['role'] == 'student') {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
        } else {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
        }
      }
    } catch (error) {
      if (context.mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
      }
    }
  }

  Future<void> _openSchoolCabinet(BuildContext context) async {
    final service = SchoolAccountService();
    final current = await service.currentUser();
    if (!context.mounted) return;
    if (current != null) {
      if (current['role'] == 'student') {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
      } else {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
      }
      return;
    }
    await _schoolAccount(context);
  }

  Future<void> _editClass(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final rawSchoolUser = prefs.getString('school_user_v1');
    if (rawSchoolUser != null) {
      try {
        final account = jsonDecode(rawSchoolUser);
        final classId = (account is Map ? account['class_id'] : null)?.toString().trim() ?? '';
        if (account is Map && account['role'] == 'student' && classId.isNotEmpty) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Класс поступает из школьной учётной записи. Если он неверный, обратись к школьному администратору.')),
          );
          return;
        }
      } catch (_) {}
    }
    await SchoolScheduleCatalog.load();
    if (!context.mounted) return;
    final result = await showDialog<String>(context: context, builder: (_) => const _StudentClassDialog());
    if (!context.mounted || result == null || result.isEmpty) return;
    await prefs.setString('student_class_name', result);
    await prefs.setString('student_class_id', result);
    if (!context.mounted) return;
    await showStudentGroupSelection(context, result);
    // The schedule tab keeps its own copy of class/groups; tell it to reload.
    notifySchoolLocalDataChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Профиль расписания: $result')),
      );
    }
  }

  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(leading: IconButton(onPressed: onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)), title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.w900))), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
      const Text('Профиль', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.person_rounded, color: c.primary), title: const Text('Имя'), subtitle: Text(userName.isEmpty ? 'Не задано' : userName), trailing: const Icon(Icons.edit_rounded), onTap: () => _editName(context))),
      Card(child: ListTile(leading: Icon(Icons.school_rounded, color: c.primary), title: const Text('Мой класс'), subtitle: const Text('Класс используется как источник базового расписания'), trailing: const Icon(Icons.edit_rounded), onTap: () => _editClass(context))),
      Card(child: ListTile(leading: Icon(Icons.groups_rounded, color: c.primary), title: const Text('Группы по предметам'), subtitle: const Text('Например: английский — 1, математика — 2'), trailing: const Icon(Icons.tune_rounded), onTap: () async { final p = await SharedPreferences.getInstance(); final cls = p.getString('student_class_name') ?? ''; if (cls.isNotEmpty && context.mounted) { await showStudentGroupSelection(context, cls); notifySchoolLocalDataChanged(); } })),
      const SizedBox(height: 18), const Text('Оформление', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.palette_rounded, color: c.primary), title: const Text('Цветовая тема'), subtitle: Text(AppPalette.name(theme)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _pickTheme(context))),
      const SizedBox(height: 18), const Text('Для сотрудников', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.verified_user_rounded, color: c.primary), title: const Text('Школьная учётная запись'), subtitle: const Text('Безопасный вход через школьный SSO и регистрация уведомлений'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _schoolAccount(context))),
      Card(child: ListTile(leading: Icon(Icons.admin_panel_settings_rounded, color: c.primary), title: const Text('Кабинет школы'), subtitle: const Text('Сотрудникам — управление по роли; ученикам — школьные оповещения'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openSchoolCabinet(context))),
      Card(child: ListTile(leading: Icon(Icons.cloud_sync_rounded, color: c.primary), title: const Text('Настройки подключения'), subtitle: const Text('Адрес API, включение онлайн-режима и проверка соединения'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openAdmin(context))),
      const SizedBox(height: 18), const Text('Приложение', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: Column(children: [ListTile(leading: Icon(Icons.info_outline_rounded, color: c.primary), title: const Text('О приложении'), subtitle: const Text('Приложение школы «Поколение»'), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutPage()))), const Divider(height: 1), ListTile(leading: Icon(Icons.restore_rounded, color: c.primary), title: const Text('Сбросить тему'), onTap: () => onThemeChanged(AppThemeType.turquoise))])),
    ]))));
  }

  Future<void> _editName(BuildContext context) async {
    final result = await showDialog<String>(context: context, builder: (_) => _EditValueDialog(title: 'Изменить имя', label: 'Имя', hint: 'Как к тебе обращаться?', initialValue: userName));
    if (!context.mounted || result == null || result.isEmpty) return;
    onNameChanged(result);
  }
  void _pickTheme(BuildContext context) => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [const Text('Цветовая тема', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 12), _ThemeTile(title: 'Жёлтая', description: 'Жёлтый → бежевый', colors: AppPalette.yellow, selected: theme == AppThemeType.yellow, onTap: () { onThemeChanged(AppThemeType.yellow); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Бирюзовая', description: 'Насыщенный бирюзовый → светло-зелёный', colors: AppPalette.turquoise, selected: theme == AppThemeType.turquoise, onTap: () { onThemeChanged(AppThemeType.turquoise); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Тёмно-синяя', description: 'Тёмно-синий → синий', colors: AppPalette.darkBlue, selected: theme == AppThemeType.darkBlue, onTap: () { onThemeChanged(AppThemeType.darkBlue); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Фиолетовая', description: 'Фиолетовый → сиреневый', colors: AppPalette.violet, selected: theme == AppThemeType.violet, onTap: () { onThemeChanged(AppThemeType.violet); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Коралловая', description: 'Коралловый → тёплый персиковый', colors: AppPalette.coral, selected: theme == AppThemeType.coral, onTap: () { onThemeChanged(AppThemeType.coral); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Зелёная', description: 'Изумрудный → мятный', colors: AppPalette.green, selected: theme == AppThemeType.green, onTap: () { onThemeChanged(AppThemeType.green); Navigator.pop(sheetContext); })])));
}

class _EditValueDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String initialValue;
  const _EditValueDialog({required this.title, required this.label, required this.hint, required this.initialValue});

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: controller, autofocus: true, textInputAction: TextInputAction.done, decoration: InputDecoration(labelText: widget.label, hintText: widget.hint), onSubmitted: (_) => Navigator.pop(context, controller.text.trim())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Сохранить')),
    ],
  );
}

class _ServerAdminLoginDialog extends StatefulWidget {
  const _ServerAdminLoginDialog();

  @override
  State<_ServerAdminLoginDialog> createState() => _ServerAdminLoginDialogState();
}

class _ServerAdminLoginDialogState extends State<_ServerAdminLoginDialog> {
  // Owned by the State so they are disposed only after the dialog's closing
  // animation has finished, not right after showDialog() returns.
  final login = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    login.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Технический вход администратора'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Только для первого запуска и восстановления доступа. Для обычной работы используй школьный SSO.'),
          const SizedBox(height: 12),
          TextField(controller: login, autofocus: true, decoration: const InputDecoration(labelText: 'Логин администратора')),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль администратора')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (login.text.trim().isEmpty || password.text.isEmpty) return;
            Navigator.pop(context, {'username': login.text.trim(), 'password': password.text});
          }, child: const Text('Войти')),
        ],
      );
}

class _ThemeTile extends StatelessWidget { final String title; final String description; final List<Color> colors; final bool selected; final VoidCallback onTap; const _ThemeTile({required this.title, required this.description, required this.colors, required this.selected, required this.onTap}); @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 10), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Container(width: 58, height: 58, decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(16))), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(description, style: const TextStyle(fontSize: 12))])), Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? colors.first : null)])))); }

// Informational screen intentionally replaces Flutter's generated About dialog:
// this keeps the app's UI focused and avoids an unnecessary system license page.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gradient = [scheme.primary, scheme.secondary];
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      ),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: .2),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Поколение',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Приложение создано для учеников и учителей школы «Поколение».',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Всё важное для школьного дня',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '«Поколение» помогает ориентироваться в здании школы, '
                          'следить за расписанием и дополнительными занятиями, '
                          'получать объявления и оповещения, вести заметки и '
                          'планировать учебные задачи.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _AboutFeature(
                  icon: Icons.map_rounded,
                  title: 'Навигация по школе',
                  description: 'Карты этажей, поиск помещений и построение маршрутов.',
                ),
                _AboutFeature(
                  icon: Icons.calendar_month_rounded,
                  title: 'Учебный день',
                  description: 'Расписание, дополнительные занятия и домашние задания.',
                ),
                _AboutFeature(
                  icon: Icons.notifications_active_rounded,
                  title: 'Школьная жизнь',
                  description: 'Объявления, оповещения и личные заметки.',
                ),
                _AboutFeature(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Локальный ИИ-помощник',
                  description: 'Помогает работать с возможностями приложения прямо на устройстве.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Для школьного сообщества «Поколение».',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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

class _AboutFeature extends StatelessWidget {
  const _AboutFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(description),
          ),
        ),
      ),
    );
  }
}
