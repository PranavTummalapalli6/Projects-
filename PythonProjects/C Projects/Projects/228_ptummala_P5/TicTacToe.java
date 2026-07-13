public class TicTacToe {
    private char[][] board;
    private Player X;
    private Player O;

    public void setBoard() {
        this.board = board;
    }

    public char[][] getBoard() {
        return board;
    }

    public void setX() {
        this.X = X;
    }

    public Player getX() {
        return X;
    }

    public void setO() {
        this.O = O;
    }

    public Player getO() {
        return O;
    }

    public TicTacToe(Player X, Player O) {
        this.X = X;
        this.O = O;
        board = new char[3][3];
        for (int i = 0; i < 3; i++) {
            for (int j = 0; j < 3; j++) {
                board[i][j] = '_';
            }
        }

    }

    public int countBlanks() {
        int count = 0;
        for (int i = 0; i < 3; i++) {
            for (int j = 0; j < 3; j++) {
                if (board[i][j] == '_') {
                    count += 1;
                }
            }
        }
        return count;
    }

    public char markerForPlayer(Player arg) {
        if (arg == X) {//symbol
            return 'X';

        } else {
            return 'O';
        }
    }

    public boolean checkWin(Player arg) {
        if (markerForPlayer(arg) == 'X') {
            for (int i = 0; i < 3; i++) {
                if (board[i][0] == 'X' && board[i][1] == 'X' && board[i][2] == 'X') {
                    return true;
                } else if (board[0][i] == 'X' && board[1][i] == 'X' && board[2][i] == 'X') {
                    return true;
                }

            }
            if (board[0][0] == 'X' && board[1][1] == 'X' && board[2][2] == 'X') {
                return true;
            } else if (board[0][2] == 'X' && board[1][1] == 'X' && board[2][0] == 'X') {
                return true;
            } else {
                return false;
            }

        } else {
            for (int i = 0; i < 3; i++) {
                if (board[i][0] == 'O' && board[i][1] == 'O' && board[i][2] == 'O') {
                    return true;
                } else if (board[0][i] == 'O' && board[1][i] == 'O' && board[2][i] == 'O') {
                    return true;
                }
            }
            if (board[0][0] == 'O' && board[1][1] == 'O' && board[2][2] == 'O') {
                return true;
            } else if (board[0][2] == 'O' && board[1][1] == 'O' && board[2][0] == 'O') {
                return true;
            } else {
                return false;
            }
        }

    }

    public boolean checkLose(Player arg) {
        if (markerForPlayer(arg) == 'X') {
            for (int i = 0; i < 3; i++) {
                if (board[i][0] == 'X' && board[i][1] == 'X' && board[i][2] == 'X') {
                    return false;
                } else if (board[0][i] == 'X' && board[1][i] == 'X' && board[2][i] == 'X') {
                    return false;
                }

            }
            if (board[0][0] == 'X' && board[1][1] == 'X' && board[2][2] == 'X') {
                return false;
            } else if (board[0][2] == 'X' && board[1][1] == 'X' && board[2][0] == 'X') {
                return false;
            } else {
                return true;
            }

        } else {
            for (int i = 0; i < 3; i++) {
                if (board[i][0] == 'O' && board[i][1] == 'O' && board[i][2] == 'O') {
                    return false;
                } else if (board[0][i] == 'O' && board[1][i] == 'O' && board[2][i] == 'O') {
                    return false;
                }
            }
            if (board[0][0] == 'O' && board[1][1] == 'O' && board[2][2] == 'O') {
                return false;
            } else if (board[0][2] == 'O' && board[1][1] == 'O' && board[2][0] == 'O') {
                return false;
            } else {
                return true;
            }
        }

    }

    public boolean checkDraw() {
        if (countBlanks() == 0) {
            return true;
        }
        if(!checkWin(X) && !checkWin(O) && !checkLose(X) && !checkLose(O)){
            return true;
        }
        return false;


    }

    public String toString() {
        String s = "";
        for (int i = 0; i < 3; i++) {
            for (int j = 0; j < 3; j++) {
                s += board[i][j] + " ";
            }
            s += "\n";
        }
        return s;
    }


    public TicTacToe[] possibleMoves(Player arg) {
        //count the number of blanks based on that create an object of tictactoe board has one of those exmpty blanks filled
        //create a deep copy of the tictactoe array or the array that is passed iterate throiug that array find blanks
        if (markerForPlayer(arg) == 'X') {
            int count = countBlanks();
            TicTacToe[] arr = new TicTacToe[count];
            int c = 0;
            for (int i = 0; i < 3; i++) {
                for (int j = 0; j < 3; j++) {
                    if (board[i][j] == '_') {
                        TicTacToe a = new TicTacToe(X, O);
                        for (int k = 0; k < 3; k++) {
                            for (int l = 0; l < 3; l++) {

                                a.board[k][l] = board[k][l];
                            }
                        }
                        a.board[i][j] = 'X';
                        arr[c++] = a;
                    }
                }
            }
            return arr;
        }
        else{
            int count = countBlanks();
            TicTacToe[] arr = new TicTacToe[count];
            int c = 0;
            for (int i = 0; i < 3; i++) {
                for (int j = 0; j < 3; j++) {
                    if (board[i][j] == '_') {
                        TicTacToe a = new TicTacToe(X, O);
                        for (int k = 0; k < 3; k++) {
                            for (int l = 0; l < 3; l++) {

                                a.board[k][l] = board[k][l];
                            }
                        }
                        a.board[i][j] = 'O';
                        arr[c++] = a;
                    }
                }
            }
            return arr;
        }
    }
}

            //check to see if first spot is empty
            //loop through the internal array make an object for that spot add it to a returnable array change that spot in the deep copy add the symbol in the next iteration check whether the symbol is there then u go to next blank
            //create an array of size count of type tictactoe





