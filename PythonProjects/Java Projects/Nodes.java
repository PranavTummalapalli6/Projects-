/**
 *  This class has code that analyzes the nodes length and assigns a print statement for each of the number leading
 *  up to the node number from 1.
 * @author Pranav Tummalapalli
 */
public class Nodes {

    /**
     *  This is the main method of nodes that prints specific statements based on the number.
     *  @param args command line args
     *
     */
    public static void main(String[] args) {

        // error checking to see if there is no argument present
        if (args.length == 0 ) {
            System.err.println("One positive number required as a command line argument.\nExample Usage: java Nodes [number]\n");
        }

        // error checking to see if there are too many arguments present
        else if (args.length > 1) {
            System.err.println("One positive number required as a command line argument.\nExample Usage: java Nodes [number]\n");
        }
        //error checking to see if the command line argument is null
        else if(args == null){
            System.err.println("One positive number required as a command line argument.\nExample Usage: java Nodes [number]\n");
        }
        else {

            //try block to assert all the values to the required print statements
            try {

                // instantiating integer i to the command line argument value
                int i = Integer.parseInt(args[0]);
                //assigning integer value of 1 to integer b
                int b = 1;
                //Empty String declaration
                String x = "";

                // instantiating the integer A to the command line argument value
                int a = Integer.parseInt(args[0]);
                //error checking to see if the argument is a negative number or zero
                if (a <= 0) throw new Exception();

                // while loop that iterates from 1 to the node command line argument and fails when the command line argument value is lower than int b
                while (b <= i) {
                    if (b == 3 || b == 12) {
                        x += " Router";
                    } else if (b % 2 != 0) {
                        x += " Client";
                    } else if (b % 2 == 0) {
                        x += " Server";
                    }
                    b++;

                }
                System.out.println(x);


            }
            //catch block that throws an exception when the nodes number is not of type integer
            catch (Exception e) {
                System.err.println("One positive number required as a command line argument.\nExample Usage: java Nodes [number]\n");
            }

        }
    }

}

