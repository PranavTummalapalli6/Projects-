public class AIPlayer extends Player {

    private String name;
    private Player opponent;

    public void setOpponent(Player opponent){
        this.opponent  = opponent;
    }
    public Player getOpponent (Player opponent){
        return opponent;
    }

    public String toString(){
        return name + " (AI)";
    }

    public AIPlayer(String name, Player opponent){
        this.name = name;
        this.opponent = opponent;
    }
    public double maxValue(TicTacToe arg){
        if(arg.checkWin(opponent)){
            return -1.0;
        }
        else if(arg.checkLose(opponent)){
            return 1.0;
        }
        else if(arg.checkDraw()){
            return 0.0;
        }
        else {

            double max = -1;
            for (int i = 0; i < arg.possibleMoves(this).length -1; i++) {
                TicTacToe a = arg.possibleMoves(this)[i];
                TicTacToe b = arg.possibleMoves(this)[i + 1];
                max = minValue(a);
                double max2 = minValue(b);
                if (max2 > max) {
                    max = max2;
                }
                //call min value for every possible move then find the highest min value
            }
            return max;
        }

        //call min recursive function for draw
    }
    public double minValue(TicTacToe arg){
        if(arg.checkWin(opponent)){
            return 1.0;
        }
        else if(!arg.checkWin(opponent)){
            return -1.0;
        }
        else if(arg.checkDraw()){
            return 0.0;
        }
        else {

            double min = 1;
            for (int i = 0; i < arg.possibleMoves(this).length -1; i++) {
                TicTacToe a = arg.possibleMoves(this)[i];
                TicTacToe b = arg.possibleMoves(this)[i + 1];
                min = maxValue(a);
                double min2 = maxValue(b);
                if (min2 < min) {
                    min = min2;
                }
                //call min value for every possible move then find the highest min value
            }
            return min;
        }
    }
    @Override
    public TicTacToe chooseMove(TicTacToe arg) {

        double max = 1;
        int count = 0;
        int ab = 0;
        for (int i = 0; i < arg.possibleMoves(this).length - 1; i++) {
            TicTacToe a = arg.possibleMoves(this)[i];
            TicTacToe b = arg.possibleMoves(this)[i + 1];
            max = minValue(a);
            double max2 = minValue(b);
            if (max2 > max) {
                max = max2;
            }
            count++;
            if (minValue(arg.possibleMoves(this)[count]) == max) {
                ab = count;
            }
            //call min value for every possible move then find the highest min value
        }
        return arg.possibleMoves(this)[ab];

    }

}
