from collections import deque


class TreeNode:
    def __init__(self, data):
        self.data = data
        self.left = None
        self.right = None


class BinarySearchTree:
    def __init__(self):
        self.root = None

    def insert(self, data):
        self.root = self._insert(self.root, data)

    def _insert(self, node, data):
        if not node:
            return TreeNode(data)
        if data < node.data:
            node.left = self._insert(node.left, data)
        elif data > node.data:
            node.right = self._insert(node.right, data)
        return node

    def search(self, data):
        return self._search(self.root, data)

    def _search(self, node, data):
        if not node:
            return False
        if data == node.data:
            return True
        if data < node.data:
            return self._search(node.left, data)
        return self._search(node.right, data)

    def delete(self, data):
        self.root = self._delete(self.root, data)

    def _delete(self, node, data):
        if not node:
            return None
        if data < node.data:
            node.left = self._delete(node.left, data)
        elif data > node.data:
            node.right = self._delete(node.right, data)
        else:
            # Node with one or no child
            if not node.left:
                return node.right
            if not node.right:
                return node.left
            # Node with two children: replace with in-order successor
            successor = node.right
            while successor.left:
                successor = successor.left
            node.data = successor.data
            node.right = self._delete(node.right, successor.data)
        return node

    def height(self):
        return self._height(self.root)

    def _height(self, node):
        if not node:
            return 0
        return 1 + max(self._height(node.left), self._height(node.right))

    def inorder(self):
        result = []
        self._inorder(self.root, result)
        print("Inorder   (L-Root-R):", result)

    def _inorder(self, node, result):
        if node:
            self._inorder(node.left, result)
            result.append(node.data)
            self._inorder(node.right, result)

    def preorder(self):
        result = []
        self._preorder(self.root, result)
        print("Preorder  (Root-L-R):", result)

    def _preorder(self, node, result):
        if node:
            result.append(node.data)
            self._preorder(node.left, result)
            self._preorder(node.right, result)

    def postorder(self):
        result = []
        self._postorder(self.root, result)
        print("Postorder (L-R-Root):", result)

    def _postorder(self, node, result):
        if node:
            self._postorder(node.left, result)
            self._postorder(node.right, result)
            result.append(node.data)

    def level_order(self):
        if not self.root:
            return
        result, queue = [], deque([self.root])
        while queue:
            node = queue.popleft()
            result.append(node.data)
            if node.left:
                queue.append(node.left)
            if node.right:
                queue.append(node.right)
        print("Level order (BFS):", result)


if __name__ == "__main__":
    bst = BinarySearchTree()

    for val in [5, 3, 7, 1, 4, 6, 8]:
        bst.insert(val)

    bst.inorder()       # [1, 3, 4, 5, 6, 7, 8] — sorted
    bst.preorder()      # [5, 3, 1, 4, 7, 6, 8]
    bst.postorder()     # [1, 4, 3, 6, 8, 7, 5]
    bst.level_order()   # [5, 3, 7, 1, 4, 6, 8]

    print("Search 4:", bst.search(4))   # True
    print("Search 9:", bst.search(9))   # False
    print("Height:", bst.height())      # 3

    bst.delete(3)
    bst.inorder()       # [1, 4, 5, 6, 7, 8]
