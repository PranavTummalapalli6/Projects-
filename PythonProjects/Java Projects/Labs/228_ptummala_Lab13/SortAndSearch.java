import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Collections;
import java.util.Scanner;
import java.io.File;

public class SortAndSearch {

	public static void main(String[] args) {


		// Task 1
		System.out.println("----------- Task 1 -----------");
		List<String> fruitList = new ArrayList<>(Arrays.asList(new String[] {"Lemon", "Orange", "Apple", "Banana"}));
		System.out.println("Unsorted fruitList:");
		for(String fruit: fruitList){
			System.out.print(fruit+" ");
		}
		System.out.println();

		// TYPE YOUR SORTING CODE HERE
		public static void createSorted() {

			for (int i = 0; i < fruitList.size() - 1; i++) {
				int lowestVal = i;

				for (int j = i + 1; j < fruitList.size(); j++) {
					if (fruitList.get(j).compareTo(fruitList.get(lowestVal)) < 0)
						lowestVal = j;
				}

				String temp = fruitList.get(i);
				fruitList.set(i, fruitList.get(lowestVal));
				fruitList.set(lowestVal, temp);
			}


			System.out.println("Sorted fruitList:");
			for (String fruit : fruitList) {
				System.out.print(fruit + " ");
			}
			System.out.println();
		}


		// search for the following fruits using Arrays class and print their index if found, otherwise print fruit is not found
		System.out.println("\nSearching within fruitsList:");
		String[] fruitsToFind = new String[]{"Apple","Guava","Banana"};

		// TYPE YOUR SEARCHING CODE HERE
		public int binarySearch(String[] fruitsToFind){
			int binarySearch(String[] fruitsToFind, String x, int low, int high) {

				// Repeat until the pointers low and high meet each other
				while (low <= high) {
					int mid = low + (high - low) / 2;

					if (fruitsToFind[mid].equals(x))
						return mid;

					if (fruitsToFind[mid].compareTo(x) > 0)
						low = mid + 1;

					else
						high = mid - 1;
				}

				return -1;
			}

		}
		
		
	
		

		// Task 2
		System.out.println();
		System.out.println("----------- Task 2 -----------");

		List<Integer> hugeArray = loadHugeArray("HugeArray.txt");

		int[] values = new int[]{25509, 11000, 63892, -1 , 69189};
		for(int i=0; i<values.length; i++){
			int index = improvedBinarySearch(hugeArray, values[i]);
			if (index >= 0)
				System.out.printf("%s found at index: %s. %n", values[i], index);
			else
				System.out.printf("Array did not contain %s. %n", values[i]);
			System.out.println();
		}

	}

	// Task 2
	// First: add a counter to count how many steps taken in binary search
	// Second: improve binary search!
	public static <T extends Comparable<T>> int improvedBinarySearch(List<T> inputList, T target) {
		int start = 0;
		int end = inputList.size();
		
		
		while(start < end){

			int mid = (end+start)/2;
			int comparison = inputList.get(mid).compareTo(target);
			if(comparison == 0){						// found it!
				return mid;
			} else if(comparison < 0){					// inputList[mid] < target
				start = mid+1;
			} else {               						// inputList[mid] > target
				end = mid;
			}
		}
		return -1;
	}



	// helper code no need to see
	public static List<Integer> loadHugeArray(String filename){
		List<Integer> list = new ArrayList<Integer>();

		try{
			Scanner sc = new Scanner(new File(filename));
			while(sc.hasNextLine()){
				int val = Integer.parseInt(sc.nextLine());
				list.add(val);
			}
		}catch(Exception e){
			System.out.println(e.getMessage());
		}
		return list;
	}

}
