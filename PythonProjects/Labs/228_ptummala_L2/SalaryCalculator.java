
import java.util.Scanner;
public class SalaryCalculator{
    public static int calculateSalary(int hour, int experience){
        int salary;
        if(hour < 30) salary = hour * 20;
        else if(hour>=30 && hour <= 40)salary = hour*30;
        else salary = 1200 + (hour-40)*50;

        if(experience < 5){
            salary = int(salary(1.02));
        }
        else{
            salary = int(salary(0.05));



    }
    public static void main(String[] args){
        Scanner sc = new Scanner(System.in);
        int hour;
        int experience;
        System.out.println("Input Hour:");

        hour = sc.nextInt();
        System.out.println("Input Experience:");

        experience = sc.nextInt();
        int salary = calculateSalary(hour,experience);
        System.out.println("Total Weekly Salary is = " + salary)

        }
    }
}