import unittest
from rounding import price


class RoundingTest(unittest.TestCase):
    def test_rounds_to_whole_units(self):
        self.assertEqual(price(2.5), 2)
        self.assertEqual(price(3.7), 4)


if __name__ == "__main__":
    unittest.main()
