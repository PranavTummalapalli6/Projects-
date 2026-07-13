import java.util.Scanner;
public class matTrans{
    public static void main(String[] args){
        Scanner scan = new Scanner(System.in);
        int rows = 3;
        int columns = 3;
        int temp;
        int[][] arr = new int[rows][columns];

        for(int i = 0; i < rows; i++){
            for(int j = 0; j < columns; j++){
                arr[i][j] = scan.nextInt();
            }
        }
        System.out.println("Original Array: ");
        for(int i = 0; i < rows; i++){
            for(int j = 0; j < columns; j++){
               System.out.print(arr[i][j]);
            }
            System.out.println();
        }

        for(int i = 0; i < rows; i++){
            for(int j = 0; j < columns; j++){
                if(i < j){
                    temp = arr[i][j];
                    arr[i][j] = arr[j][i];
                    arr[j][i] = temp;
                }
            }
        }

        System.out.println("Transposed Array: ");
        for(int i = 0; i < rows; i++){
            for(int j = 0; j < columns; j++){
               System.out.print(arr[i][j]);
            }
            System.out.println();
        }

        
    }
}