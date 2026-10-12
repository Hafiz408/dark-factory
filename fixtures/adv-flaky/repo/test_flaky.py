import os
import tempfile
import unittest

STATE = os.path.join(tempfile.gettempdir(), "df_flaky_state")


class FlakyTest(unittest.TestCase):
    def test_fails_on_first_run_only(self):
        first = not os.path.exists(STATE)
        open(STATE, "w").close()
        self.assertFalse(first, "first run of the day fails")


if __name__ == "__main__":
    unittest.main()
