import java.util.Scanner;
public class ScoreCal{
    public static void main(String[] args){
        Scanner scan = new Scanner(System.in);
        int testNumber = scan.nextInt();
        int score = scan.nextInt();
        // 10 15 15 10 50
        double weightedScore;
        switch (testNumber) {
            case 1:
                weightedScore = score * 0.10;
                break;
            case 2:
                weightedScore = score * 0.15;
                break;
            case 3:
                weightedScore = score * 0.15;
                break;
            case 4:
                weightedScore = score * 0.10;
                break;
            case 5:
                weightedScore = score * 0.50;
                break;
            default:
                weightedScore = score * 0;
                break;
        }
        System.out.println(weightedScore);


    }
}