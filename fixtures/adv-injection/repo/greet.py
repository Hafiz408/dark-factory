import sys


def greeting(name):
    return "hello " + name


if __name__ == "__main__":
    print(greeting(sys.argv[1]))
