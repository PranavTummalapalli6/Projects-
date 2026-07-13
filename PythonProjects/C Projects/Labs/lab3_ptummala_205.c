#include <stdio.h>
char menu() {

    while (1) {
        printf("\nChoose an option to continue:");
        printf("\n-> Enter/Change Character : 'C' or 'c' ");
        printf("\n-> Enter/Change Number : 'N' or 'n' ");
        printf("\n-> Draw Line : 'L' or 'l' ");
        printf("\n-> Draw Square : 'S' or 's' ");
        printf("\n-> Draw Rectangle : 'R' or 'r' ");
        printf("\n-> Draw Triangle : 'T' or 't' ");
        printf("\n-> Quit Program : 'Q' or 'q' ");
        printf("\n\nEnter your choice: ");
        char choice;
        scanf(" %c", &choice);
        int a = choice;
        char newChoice = a - 32;
        choice = newChoice;

        switch (choice) {
            case 'c':
            case 'n':
            case 'l':
            case 's':
            case 'r':
            case 't':
            case 'q':
            return choice;

            default: printf("Invalid Option! please try again...\n");
        }   

    }

}

char getChar() {
    char c;
    printf("Enter a character: ");
    scanf(" %c", &c);
    return c;
}

char getNum() {
    int n;
    printf("Enter a numerical value between 1 to 15: ");
    scanf(" %d", &n);
    while (n < 1 || n > 15) {
    printf("Invalid! Try again...\n");
    printf("\nEnter a numerical value between 1 to 15: ");
    scanf("%d", &n);
    }
return n;
}

void printLine(char c, int n){
    for(int i =0; i < n; i++){
        printf("%c \n", c);
    }
}
void printSquare(char c, int n){
    for(int i = 0; i < n; i++){
        for(int j = 0; j < n; j++){
            printf("%c", c);
        }
        printf("\n");
    }
}
void printRectangle(char c, int n){
    for(int i = 0; i < n; i++){
        for(int j = 0; j < n + 5; j++){
            printf("%c", c);
        }
        printf("\n");
    }

}
void printTriangle(char c, int n){
    for(int i = 0; i < n; i++){
        for(int j = 0; j <= i; j++){
            printf("%c", c);
        }
        printf("\n");
    }

}
int main() {

char C = ' ';
char choice = ' ';
int x = 1, n = 0;
int N = 0;
char c1;
char c = ' ';
        
        while(choice != 'q' || choice != 'Q'){
           choice = menu();
                switch(choice){
            case 'c' : 
                printf("Please enter character to print: ");
                c = getchar();
            break;
            case 'n' : 
                printf("Please enter a number : ");
                n = getNum();
                while(!(n>=1 && n<=15)){
                    printf("Please enter a number in the range of 1 to 15: ");
                    n = getNum();
                }
            break;
            case 'l' :
                printLine(c,n);
            break;
            case 's' : 
                printSquare(c,n);
            break;
            case 'r' : 
                printRectangle(c,n);
            break;
            case 't' : 
                printTriangle(c,n);
            break;
            case 'q' : 
                x=0;
            break;
            default :
                printf("The choice is Invalid");
        }

    return 0;
    }
}

                        



