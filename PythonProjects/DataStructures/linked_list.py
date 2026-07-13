class Node:
    def __init__(self, data):
        self.data = data
        self.next = None


class LinkedList:
    def __init__(self):
        self.head = None

    def append(self, data):
        new_node = Node(data)
        if not self.head:
            self.head = new_node
            return
        cur = self.head
        while cur.next:
            cur = cur.next
        cur.next = new_node

    def prepend(self, data):
        new_node = Node(data)
        new_node.next = self.head
        self.head = new_node

    def insert_at(self, index, data):
        if index == 0:
            self.prepend(data)
            return
        new_node = Node(data)
        cur = self.head
        for _ in range(index - 1):
            if not cur:
                raise IndexError("index out of range")
            cur = cur.next
        new_node.next = cur.next
        cur.next = new_node

    def delete(self, data):
        if not self.head:
            return
        if self.head.data == data:
            self.head = self.head.next
            return
        cur = self.head
        while cur.next and cur.next.data != data:
            cur = cur.next
        if cur.next:
            cur.next = cur.next.next

    def search(self, data):
        cur = self.head
        index = 0
        while cur:
            if cur.data == data:
                return index
            cur = cur.next
            index += 1
        return -1

    def reverse(self):
        prev, cur = None, self.head
        while cur:
            nxt = cur.next
            cur.next = prev
            prev = cur
            cur = nxt
        self.head = prev

    def length(self):
        count, cur = 0, self.head
        while cur:
            count += 1
            cur = cur.next
        return count

    def display(self):
        items, cur = [], self.head
        while cur:
            items.append(str(cur.data))
            cur = cur.next
        print(" -> ".join(items) + " -> None")


if __name__ == "__main__":
    ll = LinkedList()

    ll.append(1)
    ll.append(2)
    ll.append(3)
    ll.display()           # 1 -> 2 -> 3 -> None

    ll.prepend(0)
    ll.display()           # 0 -> 1 -> 2 -> 3 -> None

    ll.insert_at(2, 99)
    ll.display()           # 0 -> 1 -> 99 -> 2 -> 3 -> None

    print("Search 99:", ll.search(99))  # 2
    print("Search 7:", ll.search(7))    # -1

    ll.delete(99)
    ll.display()           # 0 -> 1 -> 2 -> 3 -> None

    ll.reverse()
    ll.display()           # 3 -> 2 -> 1 -> 0 -> None

    print("Length:", ll.length())  # 4
