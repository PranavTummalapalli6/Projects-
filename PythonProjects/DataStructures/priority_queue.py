class PriorityQueue:
    """Min-priority queue: lower priority number = higher urgency (served first)."""

    def __init__(self):
        self._heap = []  # stores (priority, item) tuples

    def enqueue(self, item, priority):
        self._heap.append((priority, item))
        self._sift_up(len(self._heap) - 1)

    def dequeue(self):
        if self.is_empty():
            raise IndexError("dequeue from empty priority queue")
        self._heap[0], self._heap[-1] = self._heap[-1], self._heap[0]
        priority, item = self._heap.pop()
        self._sift_down(0)
        return item, priority

    def peek(self):
        if self.is_empty():
            raise IndexError("peek at empty priority queue")
        return self._heap[0][1], self._heap[0][0]

    def is_empty(self):
        return len(self._heap) == 0

    def size(self):
        return len(self._heap)

    def _sift_up(self, i):
        while i > 0:
            parent = (i - 1) // 2
            if self._heap[i][0] < self._heap[parent][0]:
                self._heap[i], self._heap[parent] = self._heap[parent], self._heap[i]
                i = parent
            else:
                break

    def _sift_down(self, i):
        n = len(self._heap)
        while True:
            smallest, left, right = i, 2 * i + 1, 2 * i + 2
            if left < n and self._heap[left][0] < self._heap[smallest][0]:
                smallest = left
            if right < n and self._heap[right][0] < self._heap[smallest][0]:
                smallest = right
            if smallest == i:
                break
            self._heap[i], self._heap[smallest] = self._heap[smallest], self._heap[i]
            i = smallest

    def display(self):
        print("Priority Queue:", [(item, f"p={pri}") for pri, item in sorted(self._heap)])


if __name__ == "__main__":
    pq = PriorityQueue()

    pq.enqueue("low urgency task",    priority=3)
    pq.enqueue("critical alert",      priority=1)
    pq.enqueue("medium urgency task", priority=2)
    pq.enqueue("routine task",        priority=5)
    pq.enqueue("urgent fix",          priority=1)

    pq.display()
    print("Peek:", pq.peek())

    print("\nDequeuing in priority order:")
    while not pq.is_empty():
        item, priority = pq.dequeue()
        print(f"  [{priority}] {item}")
