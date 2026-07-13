class MinHeap:
    """Min-heap: parent is always smaller than its children."""

    def __init__(self):
        self._data = []

    def insert(self, val):
        self._data.append(val)
        self._sift_up(len(self._data) - 1)

    def extract_min(self):
        if not self._data:
            raise IndexError("extract from empty heap")
        self._data[0], self._data[-1] = self._data[-1], self._data[0]
        minimum = self._data.pop()
        self._sift_down(0)
        return minimum

    def peek(self):
        if not self._data:
            raise IndexError("peek at empty heap")
        return self._data[0]

    def size(self):
        return len(self._data)

    def _sift_up(self, i):
        while i > 0:
            parent = (i - 1) // 2
            if self._data[i] < self._data[parent]:
                self._data[i], self._data[parent] = self._data[parent], self._data[i]
                i = parent
            else:
                break

    def _sift_down(self, i):
        n = len(self._data)
        while True:
            smallest, left, right = i, 2 * i + 1, 2 * i + 2
            if left < n and self._data[left] < self._data[smallest]:
                smallest = left
            if right < n and self._data[right] < self._data[smallest]:
                smallest = right
            if smallest == i:
                break
            self._data[i], self._data[smallest] = self._data[smallest], self._data[i]
            i = smallest

    def display(self):
        print("Heap (internal array):", self._data)


class MaxHeap:
    """Max-heap: parent is always larger than its children."""

    def __init__(self):
        self._data = []

    def insert(self, val):
        self._data.append(val)
        self._sift_up(len(self._data) - 1)

    def extract_max(self):
        if not self._data:
            raise IndexError("extract from empty heap")
        self._data[0], self._data[-1] = self._data[-1], self._data[0]
        maximum = self._data.pop()
        self._sift_down(0)
        return maximum

    def peek(self):
        if not self._data:
            raise IndexError("peek at empty heap")
        return self._data[0]

    def size(self):
        return len(self._data)

    def _sift_up(self, i):
        while i > 0:
            parent = (i - 1) // 2
            if self._data[i] > self._data[parent]:
                self._data[i], self._data[parent] = self._data[parent], self._data[i]
                i = parent
            else:
                break

    def _sift_down(self, i):
        n = len(self._data)
        while True:
            largest, left, right = i, 2 * i + 1, 2 * i + 2
            if left < n and self._data[left] > self._data[largest]:
                largest = left
            if right < n and self._data[right] > self._data[largest]:
                largest = right
            if largest == i:
                break
            self._data[i], self._data[largest] = self._data[largest], self._data[i]
            i = largest

    def display(self):
        print("Heap (internal array):", self._data)


if __name__ == "__main__":
    print("--- MinHeap ---")
    min_h = MinHeap()
    for v in [5, 3, 8, 1, 4]:
        min_h.insert(v)
    min_h.display()
    print("Peek:", min_h.peek())           # 1
    print("Extract min:", min_h.extract_min())  # 1
    print("Extract min:", min_h.extract_min())  # 3
    min_h.display()

    print("\n--- MaxHeap ---")
    max_h = MaxHeap()
    for v in [5, 3, 8, 1, 4]:
        max_h.insert(v)
    max_h.display()
    print("Peek:", max_h.peek())           # 8
    print("Extract max:", max_h.extract_max())  # 8
    print("Extract max:", max_h.extract_max())  # 5
    max_h.display()
