/** 
 * On Mac/Linux:
 *  javac -cp .:junit-cs211.jar *.java         # compile everything
 *  java -cp .:junit-cs211.jar E6tester        # run tests
 * 
 * On windows replace colons with semicolons: (: with ;)
 *  javac -cp .;junit-cs211.jar *.java         # compile everything
 *  java -cp .;junit-cs211.jar E6tester        # run tests
 */
import static org.junit.Assert.*;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;

import org.junit.AfterClass;
import org.junit.BeforeClass;
import org.junit.Test;

public class P3Tester {
  public static void main(String args[]){
      org.junit.runner.JUnitCore.main("P3Tester");
    }
    private final double ERR = 0.00001;
    //robot tests
    @Test(timeout=1000) public void robot_construct() {
      Robot r = new Robot(123, false, false, false);
      assertEquals("incorrect getSerialNumber()", 123, r.getSerialNumber());
    }
    @Test(timeout=1000) public void robot_basic_capabilities(){
      Robot r1 = new Robot(123, false, false, false);
      assertEquals("incorrect canFly()", false, r1.canFly());
      assertEquals("incorrect isAutonomous()", false, r1.isAutonomous());
      assertEquals("incorrect isTeleoperated()", false, r1.isTeleoperated());

      Robot r2 = new Robot(123, true, false, false);
      assertEquals("incorrect canFly()", true, r2.canFly());
      assertEquals("incorrect isAutonomous()", false, r2.isAutonomous());
      assertEquals("incorrect isTeleoperated()", false, r2.isTeleoperated());

      Robot r3 = new Robot(123, false, true, false);
      assertEquals("incorrect canFly()", false, r3.canFly());
      assertEquals("incorrect isAutonomous()", true, r3.isAutonomous());
      assertEquals("incorrect isTeleoperated()", false, r3.isTeleoperated());

      Robot r4 = new Robot(123, false, false, true);
      assertEquals("incorrect canFly()", false, r4.canFly());
      assertEquals("incorrect isAutonomous()", false, r4.isAutonomous());
      assertEquals("incorrect isTeleoperated()", true, r4.isTeleoperated());
    }
    
    @Test(timeout=1000) public void robot_capabilities_getset() {
      Robot r1 = new Robot(123, false, false,false);
      assertEquals("incorrect getCapabilities (ctor false, false, false)", "", r1.getCapabilities());
      r1.setCapabilities(true,false,true);
      assertEquals("incorrect getCapabilities (setter true, false, true)","canFly isTeleoperated",r1.getCapabilities());
      r1.setCapabilities(true,true,true);
      assertEquals("incorrect getCapabilities (setter true, true, true)", "canFly isAutonomous isTeleoperated", r1.getCapabilities());
    }

    @Test(timeout=1000) public void robot_tostring(){
      Robot r1 = new Robot(123, false, false, false);
      assertEquals("incorrect toString() (ctor false, false, false)", "ID: 123, Capabilities: ", r1.toString());
      r1.setCapabilities(true, true, false);
      assertEquals("incorrect toString() (setter true, true, false)", "ID: 123, Capabilities: canFly isAutonomous",r1.toString());
    }

    //Drone tests
    @Test(timeout=1000) public void drone_constructor(){
      Drone d1 = new Drone(123); //single valued constructor
      assertTrue("Drone should be a subclass of Robot", d1 instanceof Robot);
      assertEquals("incorrect getSerialNumber (drone ctor)",123,d1.getSerialNumber());
    }

    @Test(timeout=1000) public void drone_capabilities(){
      Drone d1 = new Drone(123);
      assertEquals("incorrect canFly() (drone)", true, d1.canFly());
      assertEquals("incorrect isAutonomous() (drone)", false, d1.isAutonomous());
      assertEquals("incorrect isTeleoperated() (drone)", true, d1.isTeleoperated());
      //now check getCapabilities
      assertEquals("incorrect getCapabilities() (drone)", "canFly isTeleoperated", d1.getCapabilities());
    }

    //Roomba tests
    @Test(timeout=1000) public void vacuum_constructor(){
      Vacuum r1 = new Vacuum(321);
      assertTrue("Vacuum should be a subclass of Robot", r1 instanceof Robot);
      assertEquals("incorrect getSerialNumber (Vacuum ctor)",321,r1.getSerialNumber());
    }

    @Test(timeout=1000) public void vacuum_capabilities(){
      Vacuum r1 = new Vacuum(321);
      assertEquals("incorrect canClean() (vacuum)",true,r1.canClean());
      assertEquals("incorrect canFly() (vacuum)", false, r1.canFly());
      assertEquals("incorrect isAutonomous() (vacuum)", true, r1.isAutonomous());
      assertEquals("incorrect isTeleoperated() (vacuum)", false, r1.isTeleoperated());
      assertEquals("incorrect getCapabilities() (vacuum)", "isAutonomous canClean", r1.getCapabilities());
    }
    //MovieRobot subclass tests
    @Test(timeout=1000) public void movierobot_subclasses(){
      HAL9000 hal = new HAL9000(9000,false,false,false,"Hello"); //should fly regardless
      ModelB9 robo = new ModelB9(800,false,false,false,"Hello");
      WALL_E wall_e = new WALL_E(654,false,false,false,"Hello"); //should not speak regardless
      assertEquals("incorrect canFly() (hal9000)",true,hal.canFly());
      assertEquals("incorrect canFlail() (modelb9)",true,robo.canFlail());
      assertEquals("incorrect canSpeak() (wall_e)",false,wall_e.canSpeak());
      assertEquals("incorrect canClean() (wall_e)",true, wall_e.canClean());
      //quotes
      assertEquals("incorrect toString() (hal9000)","ID: 9000, Capabilities: canFly canSpeak \"I can't let you do that Dave.\"",hal.toString());
      assertEquals("incorrect toString() (modelb9)","ID: 800, Capabilities: canSpeak canFlail \"Danger, Will Robinson!\"",robo.toString());
      assertEquals("incorrect toString() (wall_e)","ID: 654, Capabilities: canClean",wall_e.toString());
    }

    /** the lines below are for setting up input/output redirection so that the
      * tests can see what is being set to the screen as well as produce its own
      * pseudo-keyboard input.  No test appear below here. */
    
    static ByteArrayOutputStream localOut, localErr;
    static ByteArrayInputStream localIn;
    static PrintStream sOut, sErr;
    static InputStream sIn;

    @BeforeClass public static void setup() throws Exception {
      sOut = System.out;
      sErr = System.err;
      sIn  = System.in;
    }
    
    @AfterClass public static void cleanup() throws Exception {
      unsetCapture();
      unsetInput();
    }
    
    private static void setCapture() {
     localOut = new ByteArrayOutputStream();
     localErr = new ByteArrayOutputStream();
     System.setOut(new PrintStream( localOut ) );
     System.setErr(new PrintStream( localErr ) );
    }

    private static String getCapture() {
     return localOut.toString().replaceAll("\\r?\\n", "\n"); 
    }

    private static void unsetCapture() {
     System.setOut( null );
     System.setOut( sOut );
     System.setErr( null );
     System.setErr( sErr );
    }
    
    private static void setInput(String input) {
      localIn = new ByteArrayInputStream(input.getBytes());
      System.setIn(localIn);
    }
    
    private static void unsetInput() throws IOException {
      if (localIn != null) localIn.close();
      System.setIn( null );
      System.setIn( sIn  );
    }


 
 
}
