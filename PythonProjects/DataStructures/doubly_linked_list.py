class Node:
    def __init__(self, data):
        self.data = data
        self.prev = None
        self.next = None


class DoublyLinkedList:
    def __init__(self):
        self.head = None
        self.tail = None

    def append(self, data):
        new_node = Node(data)
        if not self.head:
            self.head = self.tail = new_node
            return
        new_node.prev = self.tail
        self.tail.next = new_node
        self.tail = new_node

    def prepend(self, data):
        new_node = Node(data)
        if not self.head:
            self.head = self.tail = new_node
            return
        new_node.next = self.head
        self.head.prev = new_node
        self.head = new_node

    def insert_after(self, target_data, data):
        cur = self.head
        while cur and cur.data != target_data:
            cur = cur.next
        if not cur:
            raise ValueError(f"{target_data} not found")
        new_node = Node(data)
        new_node.next = cur.next
        new_node.prev = cur
        if cur.next:
            cur.next.prev = new_node
        else:
            self.tail = new_node
        cur.next = new_node

    def delete(self, data):
        cur = self.head
        while cur and cur.data != data:
            cur = cur.next
        if not cur:
            return
        if cur.prev:
            cur.prev.next = cur.next
        else:
            self.head = cur.next
        if cur.next:
            cur.next.prev = cur.prev
        else:
            self.tail = cur.prev

    def search(self, data):
        cur, index = self.head, 0
        while cur:
            if cur.data == data:
                return index
            cur = cur.next
            index += 1
        return -1

    def display_forward(self):
        items, cur = [], self.head
        while cur:
            items.append(str(cur.data))
            cur = cur.next
        print("Forward:  " + " <-> ".join(items))

    def display_backward(self):
        items, cur = [], self.tail
        while cur:
            items.append(str(cur.data))
            cur = cur.prev
        print("Backward: " + " <-> ".join(items))


if __name__ == "__main__":
    dll = DoublyLinkedList()

    dll.append(1)
    dll.append(2)
    dll.append(3)
    dll.display_forward()    # 1 <-> 2 <-> 3

    dll.prepend(0)
    dll.display_forward()    # 0 <-> 1 <-> 2 <-> 3

    dll.insert_after(2, 99)
    dll.display_forward()    # 0 <-> 1 <-> 2 <-> 99 <-> 3

    dll.display_backward()   # 3 <-> 99 <-> 2 <-> 1 <-> 0

    print("Search 99:", dll.search(99))  # 3

    dll.delete(99)
    dll.display_forward()    # 0 <-> 1 <-> 2 <-> 3

    dll.delete(0)
    dll.display_forward()    # 1 <-> 2 <-> 3

    dll.delete(3)
    dll.display_forward()    # 1 <-> 2
