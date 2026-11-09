import 'package:flutter/material.dart';

/// The llama.cpp runtime ships native binaries only. The web drawer hides this
/// entry; this page remains an explicit explanation for any deep link.
class LocalAiChatPage extends StatelessWidget {
  const LocalAiChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Локальный ИИ-помощник')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, size: 56, color: colors.primary),
                const SizedBox(height: 16),
                Text(
                  'Локальная нейросеть доступна в нативном приложении',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  'Qwen запускается через llama.cpp и использует нативные библиотеки. '
                  'Браузерная версия не скачивает и не запускает эту модель. '
                  'Остальные разделы веб-приложения работают автономно.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
