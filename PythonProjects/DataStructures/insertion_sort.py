def insertion_sort(arr):
    """
    Build the sorted array one element at a time by inserting each element
    into its correct position among already-sorted elements.
    Time: O(n²) worst  |  O(n) best (nearly sorted input)  |  Space: O(1)
    """
    arr = arr[:]
    for i in range(1, len(arr)):
        key = arr[i]
        j = i - 1
        # Shift elements that are greater than key one position to the right
        while j >= 0 and arr[j] > key:
            arr[j + 1] = arr[j]
            j -= 1
        arr[j + 1] = key
    return arr


if __name__ == "__main__":
    data = [12, 11, 13, 5, 6]
    print("Original:", data)
    print("Sorted:  ", insertion_sort(data))

    nearly_sorted = [1, 2, 4, 3, 5]
    print("\nNearly sorted:", nearly_sorted)
    print("Sorted:       ", insertion_sort(nearly_sorted))

    data2 = [9, 8, 7, 6, 5, 4, 3, 2, 1]
    print("\nReverse sorted:", data2)
    print("Sorted:        ", insertion_sort(data2))
