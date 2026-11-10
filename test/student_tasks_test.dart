import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigator/student_tasks_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      StudentTaskStore.remindersKey: false,
    });
  });

  StudentTask buildTask({
    String id = 'task-1',
    String title = 'Упражнения 12–15',
    bool done = false,
    int priority = 2,
    DateTime? dueAt,
  }) {
    final now = DateTime(2026, 11, 10, 12);
    return StudentTask(
      id: id,
      title: title,
      subject: 'Алгебра',
      description: 'Страница 42',
      dueAt: dueAt ?? DateTime(2026, 11, 12, 18),
      kind: StudentTaskKind.homework,
      priority: priority,
      done: done,
      createdAt: now,
    );
  }

  test('task serializes and restores all fields', () {
    final original = buildTask(priority: 1);
    final restored = StudentTask.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.subject, original.subject);
    expect(restored.description, original.description);
    expect(restored.dueAt, original.dueAt);
    expect(restored.kind, original.kind);
    expect(restored.priority, original.priority);
    expect(restored.done, original.done);
    expect(restored.createdAt, original.createdAt);
  });

  test('store creates, updates completion and deletes a task', () async {
    final task = buildTask();

    await StudentTaskStore.upsert(task);
    var loaded = await StudentTaskStore.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.title, task.title);
    expect(loaded.single.done, isFalse);

    final updated = await StudentTaskStore.setCompleted(task.id, true);
    expect(updated, isTrue);
    loaded = await StudentTaskStore.load();
    expect(loaded.single.done, isTrue);

    final deleted = await StudentTaskStore.delete(task.id);
    expect(deleted, isTrue);
    loaded = await StudentTaskStore.load();
    expect(loaded, isEmpty);
  });

  test('completed tasks are sorted after active tasks', () async {
    await StudentTaskStore.upsert(buildTask(id: 'done', done: true));
    await StudentTaskStore.upsert(buildTask(id: 'active', done: false));

    final loaded = await StudentTaskStore.load();
    expect(loaded.map((task) => task.id).toList(), ['active', 'done']);
  });

  test('nearest deadline is listed before a more urgent later task', () async {
    await StudentTaskStore.upsert(buildTask(
      id: 'later-urgent',
      priority: 1,
      dueAt: DateTime(2026, 11, 20, 18),
    ));
    await StudentTaskStore.upsert(buildTask(
      id: 'tomorrow-normal',
      priority: 2,
      dueAt: DateTime(2026, 11, 11, 18),
    ));

    final loaded = await StudentTaskStore.load();
    expect(
      loaded.map((task) => task.id).toList(),
      ['tomorrow-normal', 'later-urgent'],
    );
  });

  test('missing task updates return false', () async {
    expect(await StudentTaskStore.setCompleted('missing', true), isFalse);
    expect(await StudentTaskStore.delete('missing'), isFalse);
  });
}
