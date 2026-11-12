import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/dop_parser.dart';

void main() {
  group('DOP profile catalogue parser', () {
    test('reads exact values from the live profile select', () {
      const html = '''
        <select name="profile">
          <option value="">Выбери направление</option>
          <option value="0">Выберите профиль</option>
          <option value="Технологический (информационный)">Технологический профиль</option>
          <option value="Естественно-научный">Естественно-научный</option>
        </select>
      ''';

      expect(
        DopProfileCatalogParser.parse(html),
        [
          'Технологический (информационный)',
          'Естественно-научный',
        ],
      );
    });

    test('supports an unquoted option value', () {
      const html = '''
        <select id="profile">
          <option value=Гуманитарный>Гуманитарный</option>
        </select>
      ''';

      expect(
        DopProfileCatalogParser.parse(html),
        ['Гуманитарный'],
      );
    });
  });

  group('DOP catalogue and form parsers', () {
    const catalogueHtml = '''
      <form method="post" action="choose_programs.php">
        <input type="hidden" name="csrf_token" value="token-123">
        <article data-program-card="21">
          <h2>Робототехника</h2>
          <span class="direction-badge">Технологическое</span>
          <span class="hours-badge">72 часа</span>
          <span class="program-class-badge">8–10 классы</span>
          <section data-subgroup-card>
            <input
              class="discipline-checkbox"
              type="checkbox"
              checked
              name="subgroups[]"
              value="301"
              data-subgroup-id="301"
              data-program-id="21"
              data-name="Робототехника — группа 1"
              data-hours="36"
              data-limit-hours="72"
              data-schedule="[{&quot;day&quot;:1,&quot;start&quot;:3,&quot;end&quot;:4,&quot;room&quot;:&quot;214&quot;}]">
            <div class="program-subgroup-teacher">Педагог: <b>Иванов Иван</b></div>
            <span class="supplies-inline-text">Ноутбук</span>
          </section>
        </article>
        <button type="submit" name="apply" value="save">Записаться</button>
      </form>
    ''';

    test('extracts program direction, class, hours, subgroup and checkbox fields', () {
      final programs = const DopParser().parseCatalogHtml(catalogueHtml);

      expect(programs, hasLength(1));
      final program = programs.single;
      expect(program.programId, 21);
      expect(program.name, 'Робототехника');
      expect(program.direction, 'Технологическое');
      expect(program.hours, 72);
      expect(program.classes, '8–10 классы');

      final subgroup = program.subgroups.single;
      expect(subgroup.subgroupId, 301);
      expect(subgroup.name, 'Робототехника — группа 1');
      expect(subgroup.teacher, 'Иванов Иван');
      expect(subgroup.supplies, 'Ноутбук');
      expect(subgroup.selectionName, 'subgroups[]');
      expect(subgroup.selectionValue, '301');
      expect(subgroup.preselected, isTrue);
      expect(subgroup.schedule.single.day, 1);
      expect(subgroup.schedule.single.start, 3);
      expect(subgroup.schedule.single.end, 4);
      expect(subgroup.schedule.single.room, '214');
    });

    test('preserves hidden fields and submit button from the real form', () {
      final form = DopSelectionFormParser.parse(
        catalogueHtml,
        Uri.parse('https://intranet.pokolenie.school/catalog.php'),
      );

      expect(form, isNotNull);
      expect(form!.method, 'POST');
      expect(
        form.action,
        Uri.parse('https://intranet.pokolenie.school/choose_programs.php'),
      );
      expect(form.hiddenFields, hasLength(1));
      expect(form.hiddenFields.single.key, 'csrf_token');
      expect(form.hiddenFields.single.value, 'token-123');
      expect(form.submitName, 'apply');
      expect(form.submitValue, 'save');
      expect(form.hasUnsupportedControls, isFalse);
    });

    test('keeps catalogue read-only when the form contains extra named controls', () {
      const html = '''
        <form method="post" action="choose_programs.php">
          <input type="hidden" name="csrf_token" value="token-123">
          <input type="checkbox" class="discipline-checkbox" name="groups[]" value="1">
          <select name="study_period">
            <option value="morning" selected>Утро</option>
          </select>
        </form>
      ''';

      final form = DopSelectionFormParser.parse(
        html,
        Uri.parse('https://intranet.pokolenie.school/catalog.php'),
      );

      expect(form, isNotNull);
      expect(form!.hasUnsupportedControls, isTrue);
    });

    test('parses current_application.php into selected programs and schedule slots', () {
      const html = '''
        <article class="success-program-card">
          <strong class="success-program-name">Медиастудия</strong>
          <span class="hours-badge">48 часов</span>
          <div class="program-subgroup-teacher">Педагог: <b>Петрова Анна</b></div>
          <div class="program-subgroup-schedule">
            Понедельник · уроки 3–4 · Кабинет 214
            Пятница · уроки 5–6 · Кабинет 215
          </div>
        </article>
      ''';

      final choices = const DopParser().parseCurrentApplicationHtml(html);

      expect(choices, hasLength(1));
      expect(choices.single.name, 'Медиастудия');
      expect(choices.single.hours, 48);
      expect(choices.single.teacher, 'Петрова Анна');
      expect(choices.single.schedule, hasLength(2));
      expect(choices.single.schedule.first.day, 1);
      expect(choices.single.schedule.first.room, '214');
      expect(choices.single.schedule.last.day, 5);
      expect(choices.single.schedule.last.room, '215');
    });

    test('rejects a form that would send school data off-origin', () {
      const html = '''
        <form method="post" action="https://attacker.example/collect">
          <input type="checkbox" class="discipline-checkbox" name="group[]" value="1">
        </form>
      ''';

      expect(
        DopSelectionFormParser.parse(
          html,
          Uri.parse('https://intranet.pokolenie.school/catalog.php'),
        ),
        isNull,
      );
    });
  });
}
