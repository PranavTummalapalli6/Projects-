import java.util.Scanner;

public class UserPlayer extends Player {
    private String name;
    private Scanner input;


    public UserPlayer(Scanner input, String name){
        this.name = name;
        this.input = input;
    }

    public String toString(){
        return name;
    }

    public TicTacToe chooseMove(TicTacToe arg){
        System.out.println(arg);

        for(int i = 0; i < arg.possibleMoves(this).length; i++){

            System.out.println("Option " + i);
            TicTacToe a = arg.possibleMoves(this)[i];
            System.out.println(a.toString());
        }
        int a = input.nextInt();
        return arg.possibleMoves(this)[a];
    }


}
