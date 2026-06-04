import unittest

from src.shared.text_utils import compact_whitespace, redact_entities, truncate


class TextUtilsTests(unittest.TestCase):
    def test_compact_whitespace(self):
        self.assertEqual(compact_whitespace("hello\n\n   world"), "hello world")

    def test_truncate(self):
        self.assertEqual(truncate("abcdef", 4), "a...")

    def test_redact_entities(self):
        text = "Contact Aniket at aniket@example.com"
        redacted = redact_entities(
            text,
            [
                {
                    "BeginOffset": 18,
                    "EndOffset": 36,
                    "Type": "EMAIL",
                }
            ],
        )
        self.assertEqual(redacted, "Contact Aniket at [EMAIL_REDACTED]")


if __name__ == "__main__":
    unittest.main()
