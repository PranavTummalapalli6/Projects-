def merge_sort(arr):
    """
    Divide the array in half recursively, sort each half, then merge them.
    Time: O(n log n) always  |  Space: O(n) for the temporary merge arrays
    """
    if len(arr) <= 1:
        return arr

    mid = len(arr) // 2
    left  = merge_sort(arr[:mid])
    right = merge_sort(arr[mid:])
    return _merge(left, right)


def _merge(left, right):
    result = []
    i = j = 0
    while i < len(left) and j < len(right):
        if left[i] <= right[j]:
            result.append(left[i])
            i += 1
        else:
            result.append(right[j])
            j += 1
    result.extend(left[i:])
    result.extend(right[j:])
    return result


if __name__ == "__main__":
    data = [38, 27, 43, 3, 9, 82, 10]
    print("Original:", data)
    print("Sorted:  ", merge_sort(data))

    data2 = [5, 1, 4, 2, 8]
    print("\nOriginal:", data2)
    print("Sorted:  ", merge_sort(data2))

    single = [42]
    print("\nSingle element:", single)
    print("Sorted:        ", merge_sort(single))
