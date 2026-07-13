from collections import deque


class GraphAdjList:
    """Undirected graph using an adjacency list."""

    def __init__(self):
        self._adj = {}

    def add_vertex(self, v):
        if v not in self._adj:
            self._adj[v] = []

    def remove_vertex(self, v):
        if v not in self._adj:
            return
        for neighbor in self._adj[v]:
            self._adj[neighbor].remove(v)
        del self._adj[v]

    def add_edge(self, u, v):
        self.add_vertex(u)
        self.add_vertex(v)
        self._adj[u].append(v)
        self._adj[v].append(u)

    def remove_edge(self, u, v):
        if u in self._adj:
            self._adj[u] = [x for x in self._adj[u] if x != v]
        if v in self._adj:
            self._adj[v] = [x for x in self._adj[v] if x != u]

    def bfs(self, start):
        visited, queue, order = {start}, deque([start]), []
        while queue:
            node = queue.popleft()
            order.append(node)
            for neighbor in self._adj.get(node, []):
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append(neighbor)
        print("BFS:", order)

    def dfs(self, start):
        visited, order = set(), []
        self._dfs(start, visited, order)
        print("DFS:", order)

    def _dfs(self, node, visited, order):
        visited.add(node)
        order.append(node)
        for neighbor in self._adj.get(node, []):
            if neighbor not in visited:
                self._dfs(neighbor, visited, order)

    def display(self):
        print("Adjacency List:")
        for v, neighbors in sorted(self._adj.items()):
            print(f"  {v}: {neighbors}")


class GraphAdjMatrix:
    """Undirected graph using an adjacency matrix."""

    def __init__(self, num_vertices):
        self.n = num_vertices
        # n×n matrix, 0 = no edge, 1 = edge
        self._matrix = [[0] * num_vertices for _ in range(num_vertices)]

    def add_edge(self, u, v):
        self._matrix[u][v] = 1
        self._matrix[v][u] = 1

    def remove_edge(self, u, v):
        self._matrix[u][v] = 0
        self._matrix[v][u] = 0

    def has_edge(self, u, v):
        return self._matrix[u][v] == 1

    def neighbors(self, v):
        return [i for i, connected in enumerate(self._matrix[v]) if connected]

    def bfs(self, start):
        visited, queue, order = {start}, deque([start]), []
        while queue:
            node = queue.popleft()
            order.append(node)
            for neighbor in self.neighbors(node):
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append(neighbor)
        print("BFS:", order)

    def dfs(self, start):
        visited, order = set(), []
        self._dfs(start, visited, order)
        print("DFS:", order)

    def _dfs(self, node, visited, order):
        visited.add(node)
        order.append(node)
        for neighbor in self.neighbors(node):
            if neighbor not in visited:
                self._dfs(neighbor, visited, order)

    def display(self):
        print("Adjacency Matrix:")
        print("   " + " ".join(str(i) for i in range(self.n)))
        for i, row in enumerate(self._matrix):
            print(f"  {i} {row}")


if __name__ == "__main__":
    print("=== Adjacency List Graph ===")
    g = GraphAdjList()
    g.add_edge("A", "B")
    g.add_edge("A", "C")
    g.add_edge("B", "D")
    g.add_edge("C", "D")
    g.add_edge("D", "E")
    g.display()
    g.bfs("A")   # A B C D E
    g.dfs("A")   # A B D C E

    g.remove_edge("A", "C")
    print("After removing A-C:")
    g.display()

    g.remove_vertex("D")
    print("After removing vertex D:")
    g.display()

    print("\n=== Adjacency Matrix Graph ===")
    mg = GraphAdjMatrix(5)
    mg.add_edge(0, 1)
    mg.add_edge(0, 2)
    mg.add_edge(1, 3)
    mg.add_edge(2, 3)
    mg.add_edge(3, 4)
    mg.display()
    mg.bfs(0)    # [0, 1, 2, 3, 4]
    mg.dfs(0)    # [0, 1, 3, 2, 4]

    print("Has edge 0-1:", mg.has_edge(0, 1))  # True
    mg.remove_edge(0, 1)
    print("After removing 0-1, has edge 0-1:", mg.has_edge(0, 1))  # False
