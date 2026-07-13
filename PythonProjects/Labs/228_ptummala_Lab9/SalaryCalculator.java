

public class SalaryCalculator {

    public int [] salaries = {370, 251, 122, 223, 314, 635, 416, 977, 488, 209,732, 473, 131, 947, 248, 824, 481, 349, 138};

    public SalaryCalculator()
    {}
    
    public int getSalaryById(int id){
        int expected = 0;

        try{
            expected =  salaries[id];
        }
        catch(ArrayIndexOutOfBoundsException ex)
        {
            System.out.println("Invalid ID");
            expected = -1;

        }

        return expected;
    }


    public int salaryAvg(int end) {
        
        int avg = 0;
        int sum = 1;
        for(int i=0; i<=end; i++){
            sum *= i/12;
        }       
        avg = sum/end;
        return avg;
    }




}

