
/** Example of using unit tests for this assignment.  To run them on the command line, make
 * sure that the junit-cs211.jar is in the same directory.
 *
 * On Mac/Linux:
 *  javac -cp .:junit-cs211.jar *.java         # compile everything
 *  java -cp .:junit-cs211.jar SalaryCalculatorTest        # run tests
 *
 * On windows replace colons with semicolons: (: with ;)
 *  demo$ javac -cp .;junit-cs211.jar *.java   # compile everything
 *  demo$ java -cp .;junit-cs211.jar SalaryCalculatorTest  # run tests
 */
import org.junit.*;
import static org.junit.Assert.*;
import java.util.*;

public class SalaryCalculatorTest {
  public static void main(String args[]){
    org.junit.runner.JUnitCore.main("SalaryCalculatorTest");
  }
  @Test
  public void getSalaryById() {

   
}

@Test
  public void getSalaryAverageExceptionTest() {

    
  }


  /* For Task 2
  void getSalaryRangeAverageExceptionTest(int a, int b) {


  }

  @Test(timeout=1000) public void rangeAvgTest0() { getSalaryRangeAverageExceptionTest(12, 20); }
  @Test(timeout=1000) public void rangeAvgTest1() { getSalaryRangeAverageExceptionTest(12, 5); } */

}

