public class Recursion {
    public static int isPowerOf(int base, int result){
        if(result % base != 0){
            return -1;
        }
        else if(result == 1){
            return 0;
        }
        else if(result == 0){
            return -1;
        }
        else{
            return isPowerOf(base, result/base) + 1;

        }


    }
    public static void reverse(int[] array, int index){
        if (index > array.length) {
            int end = array.length - 1;
            int temp = array[index];
            array[index] = array[end];
            array[end] = temp;
            reverse(array, index + 1);

        }

    }
}


