import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'security_service.dart';

class AdminLoginDialog extends StatefulWidget {
  const AdminLoginDialog({super.key});
  @override State<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<AdminLoginDialog> {
  final login = TextEditingController();
  final password = TextEditingController();
  bool hidden = true;
  bool busy = false;
  String? error;

  @override void dispose() { login.dispose(); password.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (busy) return;
    setState(() => busy = true);
    final result = await AdminRepository().authenticate(login.text.trim(), password.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (result == null) {
      setState(() => error = 'Неверный логин, пароль или аккаунт временно заблокирован');
      return;
    }
    Navigator.pop(context, result);
  }

  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Вход для администраторов'),
    content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: login, autofocus: true, decoration: const InputDecoration(labelText: 'Логин')),
      const SizedBox(height: 10),
      TextField(controller: password, obscureText: hidden, onSubmitted: (_) => _submit(), decoration: InputDecoration(labelText: 'Пароль', suffixIcon: IconButton(onPressed: () => setState(() => hidden = !hidden), icon: Icon(hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded)))),
      if (error != null) ...[const SizedBox(height: 10), Align(alignment: Alignment.centerLeft, child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))],
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: busy ? null : _submit, child: Text(busy ? 'Проверка…' : 'Войти'))],
  );
}

class AdminRepository {
  static const _key = 'navigator_admins_v2';
  static const _legacyKey = 'navigator_admins_v1';
  static const _lockKey = 'navigator_admin_lock_v1';
  static const _auditKey = 'navigator_admin_audit_v1';

  Future<List<AdminAccount>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? prefs.getString(_legacyKey);
    if (raw == null) return [const AdminAccount(id: 'root', login: AdminAuthStore.bootstrapLogin, passwordHash: AdminAuthStore.bootstrapPasswordSha256, role: 'superadmin')];
    try {
      return (jsonDecode(raw) as List).map((e) => AdminAccount.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [const AdminAccount(id: 'root', login: AdminAuthStore.bootstrapLogin, passwordHash: AdminAuthStore.bootstrapPasswordSha256, role: 'superadmin')];
    }
  }

  Future<void> save(List<AdminAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(accounts.map((e) => e.toJson()).toList()));
  }

  Future<AdminAccount?> authenticate(String login, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final lockUntil = prefs.getInt('$_lockKey.$login') ?? 0;
    if (lockUntil > DateTime.now().millisecondsSinceEpoch) return null;
    final accounts = await list();
    for (final account in accounts) {
      if (account.active && account.login == login && PasswordHasher.verify(password, account.passwordHash)) {
        await prefs.remove('$_lockKey.$login');
        await prefs.remove('$_lockKey.$login.failures');
        // Upgrade the legacy unsalted SHA-256 hash after a successful login.
        if (!account.passwordHash.startsWith('v2\$')) {
          final upgraded = account.copyWith(passwordHash: PasswordHasher.secureDigest(password));
          final updated = accounts.map((a) => a.id == account.id ? upgraded : a).toList();
          await save(updated);
          await audit(account, 'Обновлён формат хранения пароля');
          return upgraded;
        }
        await audit(account, 'Успешный вход');
        return account;
      }
    }
    final key = '$_lockKey.$login';
    final failures = (prefs.getInt('$key.failures') ?? 0) + 1;
    if (failures >= 5) {
      await prefs.setInt(key, DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch);
      await prefs.remove('$key.failures');
    } else {
      await prefs.setInt('$key.failures', failures);
    }
    return null;
  }

  Future<void> audit(AdminAccount? account, String action, {String? target}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_auditKey);
    List<dynamic> items = [];
    try { if (raw != null) items = jsonDecode(raw) as List<dynamic>; } catch (_) {}
    items.insert(0, {
      'time': DateTime.now().toIso8601String(),
      'login': account?.login ?? 'system',
      'role': account?.role ?? 'system',
      'action': action,
      'target': target ?? '',
    });
    if (items.length > 300) items = items.take(300).toList();
    await prefs.setString(_auditKey, jsonEncode(items));
  }

  Future<List<Map<String, dynamic>>> auditLog() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_auditKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }
}

class AdminPanelPage extends StatefulWidget {
  final AdminAccount account;
  const AdminPanelPage({super.key, required this.account});
  @override State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  int tab = 0;
  List<AdminAccount> admins = [];
  List<Map<String, dynamic>> audit = [];
  final apiController = TextEditingController();
  bool saving = false;
  bool apiEnabled = false;
  String apiStatus = 'Синхронизация выключена — приложение работает локально.';

  bool can(String p) => widget.account.can(p);

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { apiController.dispose(); super.dispose(); }

  Future<void> _load() async {
    final list = await AdminRepository().list();
    final prefs = await SharedPreferences.getInstance();
    apiController.text = prefs.getString('navigator_api_url') ?? '';
    apiEnabled = prefs.getBool('navigator_api_enabled') ?? false;
    audit = await AdminRepository().auditLog();
    if (mounted) setState(() => admins = list);
  }

  Future<void> _addAdmin() async {
    if (!can(AdminPermissions.manageAdmins)) return;
    final result = await showDialog<AdminAccount>(context: context, builder: (_) => const _AdminEditor());
    if (result == null) return;
    if (admins.any((a) => a.login.toLowerCase() == result.login.toLowerCase())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Такой логин уже существует')));
      return;
    }
    admins = [...admins, result];
    await AdminRepository().save(admins);
    await AdminRepository().audit(widget.account, 'Создан администратор', target: result.login);
    await _refresh();
  }

  Future<void> _editAdmin(AdminAccount account) async {
    if (!can(AdminPermissions.manageAdmins) || account.id == 'root' && widget.account.id != 'root') return;
    final result = await showDialog<AdminAccount>(context: context, builder: (_) => _AdminEditor(existing: account));
    if (result == null) return;
    if (admins.any((a) => a.id != account.id && a.login.toLowerCase() == result.login.toLowerCase())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Такой логин уже существует')));
      return;
    }
    admins = admins.map((a) => a.id == account.id ? result : a).toList();
    await AdminRepository().save(admins);
    await AdminRepository().audit(widget.account, 'Изменён администратор', target: result.login);
    await _refresh();
  }

  Future<void> _remove(AdminAccount account) async {
    if (!can(AdminPermissions.manageAdmins) || account.id == 'root') return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Удалить администратора?'),
      content: Text('Аккаунт «${account.login}» больше не сможет войти в Navigator.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))],
    )) ?? false;
    if (!ok) return;
    admins.removeWhere((a) => a.id == account.id);
    await AdminRepository().save(admins);
    await AdminRepository().audit(widget.account, 'Удалён администратор', target: account.login);
    await _refresh();
  }

  Future<void> _refresh() async {
    final list = await AdminRepository().list();
    final log = await AdminRepository().auditLog();
    if (mounted) setState(() { admins = list; audit = log; });
  }

  Future<void> _saveApi() async {
    if (!can(AdminPermissions.manageSync)) return;
    final raw = apiController.text.trim();
    if (apiEnabled && raw.isNotEmpty && Uri.tryParse(raw)?.hasScheme != true) {
      setState(() => apiStatus = 'Укажи полный адрес, например https://example.ru/api');
      return;
    }
    setState(() => saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('navigator_api_url', raw);
    await prefs.setBool('navigator_api_enabled', apiEnabled && raw.isNotEmpty);
    await AdminRepository().audit(widget.account, 'Изменены настройки API');
    if (mounted) {
      setState(() {
        saving = false;
        apiStatus = apiEnabled && raw.isNotEmpty ? 'Синхронизация включена. Секреты OAuth и пароли в APK не сохраняются.' : 'Синхронизация выключена — приложение работает локально.';
      });
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки сервера сохранены')));
  }

  Future<void> _testApi() async {
    if (!can(AdminPermissions.manageSync)) return;
    final raw = apiController.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => apiStatus = 'Сначала укажи корректный URL сервера.');
      return;
    }
    setState(() => apiStatus = 'Проверяю соединение…');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      setState(() => apiStatus = 'Сервер отвечает: HTTP ${response.statusCode}.');
      await AdminRepository().audit(widget.account, 'Проверено подключение API');
    } catch (_) {
      if (!mounted) return;
      setState(() => apiStatus = 'Не удалось подключиться. Проверь адрес и доступность сервера.');
    }
  }

  @override Widget build(BuildContext context) {
    final sections = <({String title, IconData icon, String permission})>[
      (title: 'Администраторы', icon: Icons.manage_accounts_rounded, permission: AdminPermissions.manageAdmins),
      (title: 'Синхронизация', icon: Icons.cloud_sync_rounded, permission: AdminPermissions.manageSync),
      (title: 'Данные', icon: Icons.table_chart_rounded, permission: AdminPermissions.manageData),
      (title: 'Безопасность', icon: Icons.security_rounded, permission: AdminPermissions.manageSecurity),
      (title: 'Аудит', icon: Icons.history_rounded, permission: AdminPermissions.viewAudit),
    ].where((s) => can(s.permission)).toList();
    if (sections.isEmpty) return const Scaffold(body: Center(child: Text('Нет доступных разделов')));
    tab = tab.clamp(0, sections.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-панель', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Center(child: Text('${widget.account.login} • ${_roleName(widget.account.role)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
        ],
      ),
      body: Row(children: [
        NavigationRail(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), labelType: NavigationRailLabelType.all,
          destinations: [for (final s in sections) NavigationRailDestination(icon: Icon(s.icon), label: Text(s.title))]),
        const VerticalDivider(width: 1),
        Expanded(child: IndexedStack(index: tab, children: [
          for (final s in sections)
            s.permission == AdminPermissions.manageAdmins ? _admins() :
            s.permission == AdminPermissions.manageSync ? _sync() :
            s.permission == AdminPermissions.manageSecurity ? _security() : 
            s.permission == AdminPermissions.viewAudit ? _audit() : _data(),
        ])),
      ]),
    );
  }

  Widget _admins() => ListView(padding: const EdgeInsets.all(20), children: [
    Row(children: [const Expanded(child: Text('Администраторы', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))), if (can(AdminPermissions.manageAdmins)) FilledButton.icon(onPressed: _addAdmin, icon: const Icon(Icons.person_add_rounded), label: const Text('Добавить'))]),
    const SizedBox(height: 8),
    const Text('Права назначаются отдельно и проверяются перед каждой административной операцией.'),
    const SizedBox(height: 12),
    ...admins.map((a) => Card(child: ListTile(
      leading: CircleAvatar(child: Icon(a.role == 'superadmin' ? Icons.shield_rounded : Icons.person_rounded)),
      title: Text(a.login, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${_roleName(a.role)} • ${a.active ? 'активен' : 'отключён'}\n${a.effectivePermissions.length} прав'),
      isThreeLine: true,
      trailing: can(AdminPermissions.manageAdmins) && a.id != 'root'
          ? Wrap(children: [
              IconButton(tooltip: 'Изменить', onPressed: () => _editAdmin(a), icon: const Icon(Icons.edit_rounded)),
              IconButton(tooltip: a.active ? 'Отключить' : 'Включить', onPressed: () => _toggleAdmin(a), icon: Icon(a.active ? Icons.person_off_rounded : Icons.person_rounded)),
              IconButton(tooltip: 'Удалить', onPressed: () => _remove(a), icon: const Icon(Icons.delete_outline_rounded)),
            ])
          : null,
    ))),
  ]);

  Future<void> _toggleAdmin(AdminAccount account) async {
    if (!can(AdminPermissions.manageAdmins) || account.id == 'root') return;
    final updated = account.copyWith(active: !account.active);
    admins = admins.map((a) => a.id == account.id ? updated : a).toList();
    await AdminRepository().save(admins);
    await AdminRepository().audit(widget.account, updated.active ? 'Включён администратор' : 'Отключён администратор', target: account.login);
    await _refresh();
  }

  Widget _sync() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Серверная синхронизация', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8),
    const Text('API — отдельный контур. Секреты OAuth и пароли в APK не хранятся.'),
    const SizedBox(height: 14),
    Card(child: SwitchListTile.adaptive(
      value: apiEnabled,
      onChanged: can(AdminPermissions.manageSync) ? (value) => setState(() => apiEnabled = value) : null,
      title: const Text('Использовать API', style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(apiEnabled ? 'Онлайн-функции разрешены' : 'Только локальные данные'),
      secondary: Icon(apiEnabled ? Icons.cloud_done_rounded : Icons.cloud_off_rounded),
    )),
    const SizedBox(height: 12),
    TextField(controller: apiController, enabled: can(AdminPermissions.manageSync) && apiEnabled, maxLines: 1, textInputAction: TextInputAction.done, decoration: const InputDecoration(labelText: 'Адрес API', hintText: 'https://example.ru/api', prefixIcon: Icon(Icons.link_rounded))),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: can(AdminPermissions.manageSync) && apiEnabled ? _testApi : null, icon: const Icon(Icons.wifi_tethering_rounded), label: const Text('Проверить'))),
      const SizedBox(width: 10),
      Expanded(child: FilledButton.icon(onPressed: can(AdminPermissions.manageSync) && !saving ? _saveApi : null, icon: const Icon(Icons.save_rounded), label: Text(saving ? 'Сохраняю…' : 'Сохранить'))),
    ]),
    const SizedBox(height: 12),
    Card(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Padding(padding: const EdgeInsets.all(14), child: Text(apiStatus))),
  ]);

  Widget _data() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Управление данными', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8),
    const Text('Разделы доступны только администраторам с соответствующими правами.'),
    const SizedBox(height: 12),
    _DataTile('Classes', 'Классы и профили', can(AdminPermissions.manageData)),
    _DataTile('BaseSchedule', 'Базовое расписание каждого класса', can(AdminPermissions.manageSchedule)),
    _DataTile('Supplements', 'ДОПы: время, учитель, кабинет, место и маршрут', can(AdminPermissions.manageData)),
    _DataTile('Rooms / Places', 'Кабинеты и специализированные пространства', can(AdminPermissions.manageRooms) || can(AdminPermissions.managePlaces)),
    _DataTile('Announcements', 'Объявления по классу или всей школе', can(AdminPermissions.manageAnnouncements)),
  ]);

  Widget _security() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Безопасность', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
    const SizedBox(height: 12),
    _SecurityTile(Icons.lock_clock_rounded, 'Защита от перебора', 'После 5 неверных попыток логин блокируется на 5 минут.'),
    _SecurityTile(Icons.password_rounded, 'Пароли', 'Новые и успешно используемые старые пароли переходят на солёное многократное хеширование.'),
    _SecurityTile(Icons.shield_rounded, 'Права', 'Каждая административная операция проверяет разрешение текущего аккаунта.'),
    _SecurityTile(Icons.phone_android_rounded, 'Важно', 'Локальные права находятся в APK/хранилище устройства. Для настоящей защиты полномочий нужен сервер, который проверяет роль на своей стороне.'),
  ]);

  Widget _audit() => ListView(padding: const EdgeInsets.all(20), children: [
    Row(children: [const Expanded(child: Text('Журнал аудита', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))), IconButton(tooltip: 'Обновить', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
    const SizedBox(height: 8),
    Text('Хранится локально, последние ${audit.length} событий.'),
    const SizedBox(height: 12),
    if (audit.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Событий пока нет.'))),
    ...audit.map((e) => Card(child: ListTile(
      leading: const Icon(Icons.history_rounded),
      title: Text('${e['login'] ?? 'system'} — ${e['action'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${e['time'] ?? ''}${(e['target'] ?? '').toString().isEmpty ? '' : ' • ${e['target']}'}'),
    ))),
  ]);
}

String _roleName(String role) {
  switch (role) {
    case 'superadmin': return 'Главный администратор';
    case 'content': return 'Контент-администратор';
    default: return 'Администратор';
  }
}

class _DataTile extends StatelessWidget {
  final String title; final String subtitle; final bool enabled;
  const _DataTile(this.title, this.subtitle, this.enabled);
  @override Widget build(BuildContext context) => Card(child: ListTile(
    leading: Icon(enabled ? Icons.table_rows_rounded : Icons.lock_outline_rounded, color: enabled ? null : Theme.of(context).colorScheme.outline),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(enabled ? subtitle : 'Нет права на изменение этого раздела'),
  ));
}

class _SecurityTile extends StatelessWidget {
  final IconData icon; final String title; final String subtitle;
  const _SecurityTile(this.icon, this.title, this.subtitle);
  @override Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle)));
}

class _AdminEditor extends StatefulWidget {
  final AdminAccount? existing;
  const _AdminEditor({this.existing});
  @override State<_AdminEditor> createState() => _AdminEditorState();
}

class _AdminEditorState extends State<_AdminEditor> {
  final login = TextEditingController();
  final password = TextEditingController();
  String role = 'admin';
  bool active = true;
  final selected = <String>{};

  @override void initState() {
    super.initState();
    final a = widget.existing;
    if (a != null) {
      login.text = a.login;
      role = a.role;
      active = a.active;
      selected.addAll(a.effectivePermissions);
    } else {
      selected.addAll(AdminPermissions.forRole(role));
    }
  }

  @override void dispose(){login.dispose(); password.dispose(); super.dispose();}

  void _applyRole(String value) {
    setState(() {
      role = value;
      if (value == 'superadmin') {
        selected
          ..clear()
          ..addAll(AdminPermissions.all);
      } else if (widget.existing == null) {
        selected
          ..clear()
          ..addAll(AdminPermissions.forRole(value));
      }
    });
  }

  @override Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Новый администратор' : 'Изменить администратора'),
    scrollable: true,
    content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: login, autofocus: true, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Логин')),
      const SizedBox(height: 10),
      TextField(controller: password, obscureText: true, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: widget.existing == null ? 'Пароль' : 'Новый пароль (необязательно)', helperText: 'Не короче 8 символов')),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: role,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Роль'),
        items: const [
          DropdownMenuItem(value: 'admin', child: Text('Администратор')),
          DropdownMenuItem(value: 'content', child: Text('Контент-администратор')),
          DropdownMenuItem(value: 'superadmin', child: Text('Главный администратор')),
        ],
        onChanged: (v) => _applyRole(v ?? 'admin'),
      ),
      const SizedBox(height: 12),
      const Text('Полномочия', style: TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      ...AdminPermissions.all.map((p) => CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: selected.contains(p) || role == 'superadmin',
        onChanged: role == 'superadmin' ? null : (v) => setState(() => v == true ? selected.add(p) : selected.remove(p)),
        title: Text(AdminPermissions.labels[p] ?? p),
      )),
      SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setState(() => active = v), title: const Text('Аккаунт активен')),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () {
        final l = login.text.trim();
        if (l.length < 3) return;
        if (widget.existing == null && password.text.length < 8) return;
        final hash = password.text.isEmpty && widget.existing != null
            ? widget.existing!.passwordHash
            : PasswordHasher.secureDigest(password.text);
        Navigator.pop(context, AdminAccount(
          id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
          login: l,
          passwordHash: hash,
          role: role,
          active: active,
          permissions: role == 'superadmin' ? AdminPermissions.all.toList() : selected.toList(),
        ));
      }, child: Text(widget.existing == null ? 'Создать' : 'Сохранить')),
    ],
  );
}
