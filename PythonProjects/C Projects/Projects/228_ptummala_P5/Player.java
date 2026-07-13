public abstract class Player {
    public abstract TicTacToe chooseMove(TicTacToe arg);

    public double boardValue(TicTacToe arg){
        if (arg.checkWin(this)) {
            return 1.0;
        }
        else if(arg.checkLose(this)){
            return -1.0;
        }
        else{
            return 0;
        }
    }


}
