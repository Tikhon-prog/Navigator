import unittest

from backend.main import _lesson_number_sort_value


class ScheduleSortingTests(unittest.TestCase):
    def test_numeric_and_text_lesson_numbers_sort_safely(self):
        rows = [
            {"lesson_number": "10 урок"},
            {"lesson_number": 2},
            {"lesson_number": "3"},
            {"lesson_number": ""},
            {"lesson_number": None},
            {"lesson_number": "урок 1"},
        ]

        rows.sort(key=_lesson_number_sort_value)

        self.assertEqual(
            [_lesson_number_sort_value(row) for row in rows],
            [0, 0, 1, 2, 3, 10],
        )

    def test_missing_or_unparseable_lesson_number_defaults_to_zero(self):
        for value in (None, "", "перемена", "n/a"):
            with self.subTest(value=value):
                self.assertEqual(
                    _lesson_number_sort_value({"lesson_number": value}),
                    0,
                )


if __name__ == "__main__":
    unittest.main()
