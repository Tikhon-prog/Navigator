import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/mentor_mentees_page.dart';

void main() {
  test('mentor mentee local record preserves identity, class, selected weekdays, lessons and DOPs', () {
    const original = MentorMentee(
      id: 'mentee-1',
      lastName: 'Иванов',
      firstName: 'Иван',
      middleName: 'Иванович',
      grade: '10',
      letter: 'А',
      profile: 'информационно-технологический',
      selectedDays: {1, 3, 6},
      notes: 'Тестовая карточка',
      lessons: [
        MentorPlanEntry(
          id: 'lesson-1', day: 1, title: 'Алгебра',
          time: '08:30–09:10', teacher: 'Петров П.П.', room: '214',
        ),
      ],
      supplements: [
        MentorPlanEntry(
          id: 'dop-1', day: 3, title: 'Робототехника',
          time: '15:30–16:10', teacher: 'Сидоров С.С.',
          room: '310', group: '2',
        ),
      ],
    );

    final restored = MentorMentee.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.fullName, 'Иванов Иван Иванович');
    expect(restored.className, '10А');
    expect(restored.profile, original.profile);
    expect(restored.selectedDays, {1, 3, 6});
    expect(restored.lessons.single.title, 'Алгебра');
    expect(restored.lessons.single.time, '08:30–09:10');
    expect(restored.supplements.single.title, 'Робототехника');
    expect(restored.supplements.single.group, '2');
  });
}
