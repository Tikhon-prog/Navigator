import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/dop_parser.dart';

void main() {
  group('DOP profile catalogue parser', () {
    test('reads exact values from the live profile select', () {
      const html = '''
        <select name="profile" id="profile_select">
          <option value="">Выберите профиль</option>
          <option value="инженерно-математический">
            Инженерно-математический
          </option>
          <option value="медико-биологический">Медико-биологический</option>
          <option value="агротехнологический">Агротехнологический</option>
          <option value="информационно-технологический">
            Информационно-технологический
          </option>
          <option value="социально-гуманитарный">
            Социально-гуманитарный
          </option>
        </select>
      ''';

      expect(
        DopProfileCatalogParser.parse(html),
        DopStudent.grade10Profiles,
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

    test('preserves hidden fields and submit button from an open form', () {
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
      expect(form.selectionLocked, isFalse);
      expect(form.hasUnsupportedControls, isFalse);
    });

    test('does not treat an initially disabled submit button as closed registration', () {
      const html = '''
        <form method="post" action="save.php" id="disciplines-form">
          <input type="hidden" name="csrf_token" value="token-123">
          <input class="discipline-checkbox" type="checkbox"
              name="choices[]" value="21:301"
              data-program-id="21" data-subgroup-id="301">
          <button type="submit" id="submit-selection" disabled>
            Отправить заявку
          </button>
        </form>
      ''';

      final form = DopSelectionFormParser.parse(
        html,
        Uri.parse('https://intranet.pokolenie.school/disciplines.php'),
      );

      expect(form, isNotNull);
      expect(form!.selectionLocked, isFalse);
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
          <div class="success-program-title-row">
            <strong class="success-program-name">Медиастудия</strong>
          </div>
          <span class="hours-badge">2 ч/нед.</span>
          <div class="program-subgroup-teacher">
            <span>Преподаватель</span><b>Тестовый преподаватель</b>
          </div>
          <div class="program-subgroup-schedule">
            <span>Понедельник · уроки 3–4 · 214 КАБИНЕТ</span>
            <span>Пятница · уроки 5–6 · 215 КАБИНЕТ</span>
          </div>
        </article>
      ''';

      final choices = const DopParser().parseCurrentApplicationHtml(html);

      expect(choices, hasLength(1));
      expect(choices.single.name, 'Медиастудия');
      expect(choices.single.hours, 2);
      expect(choices.single.teacher, 'Тестовый преподаватель');
      expect(choices.single.schedule, hasLength(2));
      expect(choices.single.schedule.first.day, 1);
      expect(choices.single.schedule.first.room, '214');
      expect(choices.single.schedule.last.day, 5);
      expect(choices.single.schedule.last.room, '215');
    });


    test('recognizes the real intranet save endpoint and closed selection state', () {
      const html = '''
        <form
          action="https://intranet.pokolenie.school/save.php"
          method="post"
          id="disciplines-form"
          class="selection-locked"
          data-fresh-selection="1"
          aria-disabled="true">
          <input type="hidden" name="csrf_token" value="fixture-token">
          <article class="discipline-card program-card profile-theme profile-theme--engineering"
              data-card="" data-program-card="188">
            <h2>Тестовая инженерная программа</h2>
            <span class="hours-badge">4 ч/нед.</span>
            <span class="program-class-badge">8–10 классы</span>
            <div class="program-subgroups is-single">
              <section class="program-subgroup" data-subgroup-card="">
                <input class="discipline-checkbox" type="checkbox"
                    name="choices[]" value="188:226" id="choice-188-226"
                    checked disabled aria-disabled="true"
                    data-program-id="188" data-subgroup-id="226"
                    data-hours="4" data-limit-hours="4"
                    data-name="Тестовая инженерная программа"
                    data-schedule="[{&quot;day&quot;:5,&quot;start&quot;:10,&quot;end&quot;:11,&quot;room&quot;:&quot;106&quot;}]">
                <div class="program-subgroup-teacher">
                  <span>Преподаватель</span><b>Тестовый преподаватель</b>
                </div>
                <div class="program-subgroup-schedule">
                  <span>Пятница · уроки 10–11 · 106 КАБИНЕТ</span>
                </div>
              </section>
            </div>
          </article>
          <div id="selection-bar" data-max-hours="10"></div>
          <button type="submit" id="submit-selection" disabled aria-disabled="true">
            Отправить заявку
          </button>
        </form>
      ''';

      final parser = const DopParser();
      final programs = parser.parseCatalogHtml(html);
      expect(programs, hasLength(1));
      expect(programs.single.programId, 188);
      expect(programs.single.name, 'Тестовая инженерная программа');
      expect(programs.single.hours, 4);
      expect(programs.single.classes, '8–10 классы');
      expect(programs.single.direction, isEmpty);
      final subgroup = programs.single.subgroups.single;
      expect(subgroup.selectionName, 'choices[]');
      expect(subgroup.selectionValue, '188:226');
      expect(subgroup.selectionDisabled, isTrue);
      expect(subgroup.preselected, isFalse);
      expect(subgroup.teacher, 'Тестовый преподаватель');
      expect(subgroup.schedule.single.day, 5);
      expect(subgroup.schedule.single.room, '106');

      final form = DopSelectionFormParser.parse(
        html,
        Uri.parse('https://intranet.pokolenie.school/disciplines.php'),
      );
      expect(form, isNotNull);
      expect(form!.action,
          Uri.parse('https://intranet.pokolenie.school/save.php'));
      expect(form.method, 'POST');
      expect(form.hiddenFields, hasLength(1));
      expect(form.hiddenFields.single.key, 'csrf_token');
      expect(form.hiddenFields.single.value, 'fixture-token');
      expect(form.selectionLocked, isTrue);
      expect(form.maxHours, 10);
      expect(form.hasUnsupportedControls, isFalse);
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
