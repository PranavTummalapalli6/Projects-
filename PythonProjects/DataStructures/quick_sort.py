def quick_sort(arr):
    """
    Pick a pivot, partition the array so everything smaller is left of the pivot
    and everything larger is right, then recurse on both halves.
    Time: O(n log n) average  |  O(n²) worst (sorted input with bad pivot)  |  Space: O(log n)
    """
    arr = arr[:]
    _quick_sort(arr, 0, len(arr) - 1)
    return arr


def _quick_sort(arr, low, high):
    if low < high:
        pivot_idx = _partition(arr, low, high)
        _quick_sort(arr, low, pivot_idx - 1)
        _quick_sort(arr, pivot_idx + 1, high)


def _partition(arr, low, high):
    # Median-of-three pivot to reduce worst-case likelihood
    mid = (low + high) // 2
    if arr[mid] < arr[low]:
        arr[low], arr[mid] = arr[mid], arr[low]
    if arr[high] < arr[low]:
        arr[low], arr[high] = arr[high], arr[low]
    if arr[mid] < arr[high]:
        arr[mid], arr[high] = arr[high], arr[mid]
    pivot = arr[high]

    i = low - 1
    for j in range(low, high):
        if arr[j] <= pivot:
            i += 1
            arr[i], arr[j] = arr[j], arr[i]
    arr[i + 1], arr[high] = arr[high], arr[i + 1]
    return i + 1


if __name__ == "__main__":
    data = [10, 7, 8, 9, 1, 5]
    print("Original:", data)
    print("Sorted:  ", quick_sort(data))

    data2 = [3, 6, 8, 10, 1, 2, 1]
    print("\nOriginal:", data2)
    print("Sorted:  ", quick_sort(data2))

    already_sorted = [1, 2, 3, 4, 5]
    print("\nAlready sorted:", already_sorted)
    print("Sorted:        ", quick_sort(already_sorted))
