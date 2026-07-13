class Stack:
    def __init__(self):
        self._data = []

    def push(self, item):
        self._data.append(item)

    def pop(self):
        if self.is_empty():
            raise IndexError("pop from empty stack")
        return self._data.pop()

    def peek(self):
        if self.is_empty():
            raise IndexError("peek at empty stack")
        return self._data[-1]

    def is_empty(self):
        return len(self._data) == 0

    def size(self):
        return len(self._data)

    def display(self):
        print("Stack (top →):", self._data[::-1])


if __name__ == "__main__":
    s = Stack()

    s.push(10)
    s.push(20)
    s.push(30)
    s.display()                  # [30, 20, 10]

    print("Peek:", s.peek())     # 30
    print("Pop:", s.pop())       # 30
    s.display()                  # [20, 10]

    print("Size:", s.size())     # 2
    print("Empty?", s.is_empty()) # False

    s.pop()
    s.pop()
    print("Empty?", s.is_empty()) # True
