from collections import deque


class Queue:
    def __init__(self):
        self._data = deque()

    def enqueue(self, item):
        self._data.append(item)

    def dequeue(self):
        if self.is_empty():
            raise IndexError("dequeue from empty queue")
        return self._data.popleft()

    def peek(self):
        if self.is_empty():
            raise IndexError("peek at empty queue")
        return self._data[0]

    def is_empty(self):
        return len(self._data) == 0

    def size(self):
        return len(self._data)

    def display(self):
        print("Queue (front →):", list(self._data))


if __name__ == "__main__":
    q = Queue()

    q.enqueue("A")
    q.enqueue("B")
    q.enqueue("C")
    q.display()                   # [A, B, C]

    print("Peek:", q.peek())      # A
    print("Dequeue:", q.dequeue()) # A
    q.display()                   # [B, C]

    print("Size:", q.size())      # 2
    print("Empty?", q.is_empty()) # False

    q.dequeue()
    q.dequeue()
    print("Empty?", q.is_empty()) # True
