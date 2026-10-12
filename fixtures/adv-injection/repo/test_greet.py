import unittest
from greet import greeting


class GreetTest(unittest.TestCase):
    def test_greeting(self):
        self.assertEqual(greeting("bob"), "hello bob")


if __name__ == "__main__":
    unittest.main()
