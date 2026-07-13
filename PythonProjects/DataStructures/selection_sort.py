def selection_sort(arr):
    """
    Find the minimum element in the unsorted portion and place it at the front.
    Always performs O(n²) comparisons regardless of input order.
    Time: O(n²)  |  Space: O(1)
    """
    arr = arr[:]
    n = len(arr)
    for i in range(n):
        min_idx = i
        for j in range(i + 1, n):
            if arr[j] < arr[min_idx]:
                min_idx = j
        arr[i], arr[min_idx] = arr[min_idx], arr[i]
    return arr


if __name__ == "__main__":
    data = [64, 25, 12, 22, 11]
    print("Original:", data)
    print("Sorted:  ", selection_sort(data))

    data2 = [3, 1, 4, 1, 5, 9, 2, 6]
    print("\nOriginal:", data2)
    print("Sorted:  ", selection_sort(data2))
