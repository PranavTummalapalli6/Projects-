def bubble_sort(arr):
    """
    Repeatedly swap adjacent elements that are out of order.
    Each pass bubbles the largest unsorted element to its final position.
    Time: O(n²) average/worst  |  Space: O(1)
    """
    arr = arr[:]  # work on a copy
    n = len(arr)
    for i in range(n):
        swapped = False
        for j in range(0, n - i - 1):
            if arr[j] > arr[j + 1]:
                arr[j], arr[j + 1] = arr[j + 1], arr[j]
                swapped = True
        # Early exit: if no swaps occurred the array is already sorted
        if not swapped:
            break
    return arr


if __name__ == "__main__":
    data = [64, 34, 25, 12, 22, 11, 90]
    print("Original:", data)
    print("Sorted:  ", bubble_sort(data))

    already_sorted = [1, 2, 3, 4, 5]
    print("\nAlready sorted:", already_sorted)
    print("Sorted:        ", bubble_sort(already_sorted))

    reverse_sorted = [5, 4, 3, 2, 1]
    print("\nReverse sorted:", reverse_sorted)
    print("Sorted:        ", bubble_sort(reverse_sorted))
