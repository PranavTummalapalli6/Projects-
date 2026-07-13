/** Example of using unit tests for this assignment.  To run them on the command line, make
* sure that the junit-cs211.jar is in the same directory.
* junit-cs211.jar is a version of JUnit 4
* On Mac/Linux:
*  javac -cp .:junit-cs211.jar *.java         # compile everything
*  java -cp .:junit-cs211.jar E2Tester        # run tests
*
* On windows replace colons with semicolons: (: with ;)
*  demo$ javac -cp .;junit-cs211.jar *.java   # compile everything
*  demo$ java -cp .;junit-cs211.jar E2Tester  # run tests
*/
import org.junit.*;
import static org.junit.Assert.*;
import java.util.*;
import java.lang.reflect.*;

public class E2Tester {
  // starting test values, be sure to add more
  public static final Object[][][] TEST_VALUES = {
    {
      {MeasuringUnit.METERS, 1},
      {MeasuringUnit.METERS, 1, 1},
      {MeasuringUnit.METERS, 2},
      {MeasuringUnit.METERS, 2, 3},
      {MeasuringUnit.METERS, 3, 3 }
    },

          {
            null
          },
          {
            {0}
          },

          {
          {MeasuringUnit.METERS, -1},
          {MeasuringUnit.METERS, -1, -1},
          {MeasuringUnit.METERS, -2},
          {MeasuringUnit.METERS, -1, 1},
          },

  {
          {MeasuringUnit.METERS, 9223372036854775807l, 1},
          {MeasuringUnit.METERS, 2147483647, 1},
          {MeasuringUnit.METERS, 9223372036854775807l},//long limit
          {MeasuringUnit.METERS, 2147483647},//int limit
  },
          {
                  {MeasuringUnit.METERS, 2},
                  {MeasuringUnit.METERS, 2, 1},
                  {MeasuringUnit.METERS, 5},
                  {MeasuringUnit.METERS, 6,2},
                  {MeasuringUnit.METERS, 3,2},
          },
          {
                  {MeasuringUnit.METERS, 3},
                  {MeasuringUnit.FEET, 3, 5},
                  {MeasuringUnit.FEET, 6},
                  {MeasuringUnit.METERS, 4,2},
                  {MeasuringUnit.METERS, 7,2},
          },
          {
                  {MeasuringUnit.METERS, 1},
                  {MeasuringUnit.METERS, 3, 1},
                  {MeasuringUnit.METERS, 8},
                  {MeasuringUnit.METERS, 4,8},
                  {MeasuringUnit.METERS, 1,8},
          },
          {
                  {MeasuringUnit.METERS, 6,2},
                  {MeasuringUnit.METERS, 4,8},
                  {MeasuringUnit.METERS, 3,2},
          }

  };
  // same goes for the expected results
  public static final Object[][] EXPECTED_RESULTS ={
    {
      21l,
      "[Square: {_side: 1, side: 1}, Rectangle: {otherSide: 1, side: 1}, Square: {_side: 2, side: 2}, Rectangle: {otherSide: 3, side: 2}, Rectangle: {otherSide: 3, side: 3}]"
    },
    {
      null//null pointer exception
    },
          {
            0//Illegal argument exception
          },
    {
      0,
      null//illegal argument exception
    },
    {
        0,
        null    //Arithmetic Exception

    },
          {
            49l,
                  "[Square: {_side: 2, side: 2}, Rectangle: {otherSide: 1, side: 2}, Square: {_side: 5, side: 5}, Rectangle: {otherSide: 2, side: 6}, Rectangle: {otherSide: 2, side: 3}]"
          },
          {
            82l,
                  "[Square: {_side: 3, side: 3}, Rectangle: {otherSide: 5, side: 3}, Square: {_side: 6, side: 6}, Rectangle: {otherSide: 2, side: 4}, Rectangle: {otherSide: 2, side: 7}]"
          },
          {
            108l,
                  "[Square: {_side: 1, side: 1}, Rectangle: {otherSide: 1, side: 3}, Square: {_side: 8, side: 8}, Rectangle: {otherSide: 8, side: 4}, Rectangle: {otherSide: 8, side: 1}]"
          },
          {
            50l,
                  "[Rectangle: {_side: 2, side: 6}, Rectangle: {otherSide: 8, side: 4}, Rectangle: {_side: 2, side: 3}]"
          }

  };
  public static void main(String args[]){
    org.junit.runner.JUnitCore.main("E2Tester");
  }
  public static void testShapeManager(Object[][] values, long totalArea, String shapeState) throws CheckedRuntimeException{
    ShapeManager sm = new ShapeManager(values);
    AreaCalculator ac  = sm;
    long currentResult = ac.getTotalArea();

    assertTrue("Incorrect total area: "+currentResult+", expected: "+ totalArea,  currentResult== totalArea);
    String currentShapeState = Arrays.deepToString(sm.getShapes());
    assertTrue("Incorrect shapes state: \n"+currentShapeState+" \nExpected: \n"+ shapeState,  currentShapeState.equals(shapeState));
  }
  // this test passes
  @Test(timeout=1000) public void shapeManagerGetTotalArea_00() {
    try{
      testShapeManager(
      E2Tester.TEST_VALUES[0],
      (long) E2Tester.EXPECTED_RESULTS[0][0],
      (String) E2Tester.EXPECTED_RESULTS[0][1]
      );
    }catch(CheckedRuntimeException e){
      // DEFCON 1 !!!!
    }finally{
      // YOLO
    }
  }
  // this test fails, note that the NPE is not masked, fix it
  @Test(expected=CheckedRuntimeException.class) public void shapeManagerGetTotalArea_01() throws CheckedRuntimeException{
    try {
      testShapeManager(
              E2Tester.TEST_VALUES[1],
              (long) E2Tester.EXPECTED_RESULTS[1][0],
              (String) E2Tester.EXPECTED_RESULTS[1][1]
      );
    }catch(CheckedRuntimeException e){
      throw new NullPointerException();
    }
  }

  @Test(expected=CheckedRuntimeException.class) public void shapeManagerGetTotalArea_02() throws CheckedRuntimeException{
    try {
      testShapeManager(
              E2Tester.TEST_VALUES[2],
              (long) E2Tester.EXPECTED_RESULTS[2][0],
              (String) E2Tester.EXPECTED_RESULTS[2][1]
      );
    }catch(CheckedRuntimeException e){
      throw new IllegalArgumentException();
    }
  }
  @Test(expected=CheckedRuntimeException.class) public void shapeManagerGetTotalArea_03() throws CheckedRuntimeException{
    try {
      testShapeManager(
              E2Tester.TEST_VALUES[3],
              (long) E2Tester.EXPECTED_RESULTS[3][0],
              (String) E2Tester.EXPECTED_RESULTS[3][1]
      );
    }catch(CheckedRuntimeException e){
      throw new IllegalArgumentException();
    }
  }
  @Test(expected=CheckedRuntimeException.class) public void shapeManagerGetTotalArea_04() throws CheckedRuntimeException{
    try {
      testShapeManager(
              E2Tester.TEST_VALUES[4],
              (long) E2Tester.EXPECTED_RESULTS[3][0],
              (String) E2Tester.EXPECTED_RESULTS[3][1]
      );
    }catch(CheckedRuntimeException e){
      throw new ArithmeticException();
    }
  }
  @Test(timeout=1000) public void shapeManagerGetTotalArea_05() {
    try{
      testShapeManager(
              E2Tester.TEST_VALUES[5],
              (long) E2Tester.EXPECTED_RESULTS[4][0],
              (String) E2Tester.EXPECTED_RESULTS[4][1]
      );
    }catch(CheckedRuntimeException e){
      // DEFCON 1 !!!!
    }finally{
      // YOLO
    }
  }
  @Test(timeout=1000) public void shapeManagerGetTotalArea_06() {
    try{
      testShapeManager(
              E2Tester.TEST_VALUES[6],
              (long) E2Tester.EXPECTED_RESULTS[5][0],
              (String) E2Tester.EXPECTED_RESULTS[5][1]
      );
    }catch(CheckedRuntimeException e){
      //something
    }finally{
      //something
    }
  }
  @Test(timeout=1000) public void shapeManagerGetTotalArea_07() {
    try{
      testShapeManager(
              E2Tester.TEST_VALUES[7],
              (long) E2Tester.EXPECTED_RESULTS[6][0],
              (String) E2Tester.EXPECTED_RESULTS[6][1]
      );
    }catch(CheckedRuntimeException e){
      // DEFCON 1 !!!!
    }finally{
      // YOLO
    }
  }
  @Test(timeout=1000) public void RectangleGetTotalArea_01() {
    try{
      testShapeManager(
              E2Tester.TEST_VALUES[8],
              (long) E2Tester.EXPECTED_RESULTS[7][0],
              (String) E2Tester.EXPECTED_RESULTS[7][1]
      );
    }catch(CheckedRuntimeException e){
      // DEFCON 1 !!!!
    }finally{
      // YOLO
    }
  }

}
