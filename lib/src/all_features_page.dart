part of '../main.dart';

/// Одна функция приложения в разделе «Все функции».
class AppFeature {
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final String keywords;
  final Future<void> Function() open;
  const AppFeature({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.open,
    this.keywords = '',
  });

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '$title $subtitle $category $keywords'.toLowerCase().contains(q);
  }
}

/// Все функции приложения по разделам с поиском по названию и описанию.
class AllFeaturesPage extends StatefulWidget {
  final List<AppFeature> features;
  const AllFeaturesPage({super.key, required this.features});

  @override
  State<AllFeaturesPage> createState() => _AllFeaturesPageState();
}

class _AllFeaturesPageState extends State<AllFeaturesPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = widget.features.where((f) => f.matches(_query)).toList();
    final categories = <String>[];
    for (final feature in shown) {
      if (!categories.contains(feature.category)) categories.add(feature.category);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Все функции')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Найти функцию',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 14),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('Ничего не найдено', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                ),
              for (final category in categories) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text(
                    category.toUpperCase(),
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                for (final feature in shown.where((f) => f.category == category))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Icon(feature.icon, color: scheme.primary),
                        title: Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(feature.subtitle),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => feature.open(),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
