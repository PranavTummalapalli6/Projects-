import java.awt.FlowLayout;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import javax.swing.JFrame;
import javax.swing.JFrame;
import javax.swing.JLabel;
public class Task 
{
    public static class nested extends JFrame 
    {
        private JLabel item1;
        private JLabel item2;
        private JLabel item3;



        public nested()
        {
            super("The title bar");

            setLayout(new FlowLayout());
            item1 = new JLabel("This is a sentence..");

            item1.setToolTipText("THIS WILL BE HOVER");
            add(item1);

        }
    }
   public static void task1()
   {     
       ArrayList<Integer> arrayList = new ArrayList<>();
       NSeries nSum = (n) -> n*(n-1)/2;
       for(int i=1; i<=10; i++){
           arrayList.add(nSum.calculate_NSeries(i));
       }

       arrayList.forEach((v)->System.out.println("Series value at index "+ arrayList.indexOf(v)+ " is: "+ v));


   }
    public static void main(String[] args)
    {   task1();
      nested bucky = new nested();
      bucky.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
      bucky.setSize(275,180);
      bucky.setVisible(true);

    }
}
