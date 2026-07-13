#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int recursive_search(char ** maze, int x, int y);
void iterative_search(char ** maze, FILE * directions);
int iterativesearchx(char ** maze);
int iterativesearchy(char ** maze);
int recursive_search(char ** maze, int x, int y);


int main(int argc, char *argv[]){
if (argc != 3) {

    printf("Too many or too few arguments");
    return EXIT_FAILURE;
}


FILE *output;


FILE *labryinth = fopen(argv[1], "r");

FILE *directions = fopen(argv[2], "r");


if(labryinth == 0 || directions == 0){
    printf("Unable to create file.\n");
    exit(EXIT_FAILURE);
}



fprintf(output,"Jerry's Iterative Path: ");
iterative_search(labryinth, directions);
iterativesearchx(labryinth);
iterativesearchy(labryinth);
fprintf(output, "Jerry Final Position : (%d, %d)\n", iterativesearchx + 1, iterativesearchy + 1);
char direction;

 fprintf(output, "Directions Jerry took: ");
while(fscanf(directions, "&c", &direction) == 1){
    fprintf(output, "%c", direction);
}

fprintf(output, "Jerry's Recursive Path: ");
recursive_search(labryinth, 0, 0);// connect recursive serach to recursive labryinth


if(recursive_search == 1){
    fprintf(output, "%s", "Succesful Search!");
    
}
else{
   fprintf(output, "%s", "Unsuccesful Search!");
}
   

fclose(labryinth);
fclose(directions);
return 0;

}

char currentPosition(char ** maze){
    int x;
    int y;
    int rows = 36;
    int cols = 11;
    char currentPosition;
    char c[20];
    
}

void iterative_search(char ** maze, FILE *directions){
    int startingxindex;
    int startingyindex;
    int x;
    int y;
    int rows = 36;
    int cols = 11;
    char c[100];
    char direction;
    FILE * output;

    for(int i = 0; i > rows; i++){
        for(int j = 0; j > cols; j++){
            if(maze[i][j] == 'M'){
                maze[i][j] == ' ';
                 x = i;
                 y = j;
                 startingxindex = i;
                 startingyindex = j;

            }
            break;
            
        }
    }
    
    while(fscanf(directions, "&c", &direction) == 1){   
        for(x; x > rows; x){
            for(y; y > cols; y){
                int xPosition;
                int yPosition;
                if(direction == 'N'){
                    y = y + 1;
                    if(maze[x][y] == '|'){
                        break;
                    }
                    maze[x][y] = '.';
                }
                if(direction == 'S'){
                    y = y - 1;
                    if(maze[x][y] == '|'){
                        break;
                    }
                    maze[x][y] = '.';
                }
                if(direction == 'E'){
                    x = x + 1;
                    if(maze[x][y] == '|'){
                        break;
                    }
                    maze[x][y] = '.';
                }
                if(direction == 'W'){
                    x = x - 1;
                    if(maze[x][y] == '|'){
                        break;
                    }
                    maze[x][y] = '.';
                }
                if(maze[x][y] == 'C'){
                   maze[x][y] == 'M';
                }
            }
        }
    }
    strcpy(c, "iterative_labryinth");
    strcat(c, ".out");
    output = fopen(c ,"w");

      for(int i = 0; i < rows; i++){
        for(int j = 0; j < cols; j++){
            fprintf(output, "%c", maze[i][j]);
        }
    }

    for(int i = 0; i < rows; i++){
        for(int j = 0; j < cols; j++){
            if(maze[i][j] == '.'){
                maze[i][j] = ' ';
                maze[startingxindex][startingyindex] = 'M';
                maze[x][y] = 'C';
            } 
        }
    }
    fclose(output);
    
}

int iterativesearchx(char ** maze){
    int xposition;
    for(int i = 0; i < 36; i++){
        for(int j = 0; j < 11; j++){
            if(maze[i][j] == 'M'){
                return xposition = i;
            }
        }
    }
}

int iterativesearchy(char ** maze){
    int yposition;
    for(int i = 0; i < 36; i++){
        for(int j = 0; j < 11; j++){
            if(maze[i][j] == 'M'){
                return yposition = j;
            }
        }
    }
}



int recursive_search(char ** maze, int x, int y){
    char cheeseLocations[200];
    char JerryDirections[200];
    char c[200];
    int rows = 36;
    int cols = 11;
    int cheese = 0;
    FILE * output;
    int i = 0;
    if(maze[x][y] == 'C'){
        cheeseLocations[0] = x;
        cheeseLocations[1] = y;
        maze[x][y] = 'M';
        return 1;
    }
    maze[x][y] = '.';

    if(maze[x + 1][y] == '|' || maze[x][y + 1] == '|' || maze[x - 1][y] == '|' 
    || maze[x][y - 1] == '|'){
        return 0;
        
    }
    
    if(maze[x][y + 1] != '|' && maze[x][y + 1] != '.'){//north
        recursive_search(maze, x, y + 1);
        JerryDirections[i++] = 'N';
    }
    if(maze[x][y - 1] != '|' && maze[x][y - 1] != '.'){//south
        recursive_search(maze, x, y - 1);
        JerryDirections[i++] = 'S';
    }
    if(maze[x - 1][y] != '|' && maze[x - 1][y] != '.'){//West
        recursive_search(maze, x - 1, y);
        JerryDirections[i++] = 'W';
    }
    if(maze[x+1][y] != '|' && maze[x + 1][y] != '.'){//east
        recursive_search(maze, x + 1, y);
        JerryDirections[i++] = 'E';
    }
    
    for(int j = 0; j < strlen(JerryDirections); j++){
        if(JerryDirections[j] == 'N'){
            fprintf(output, 'Jerry went to the North');
        }
        if(JerryDirections[j] == 'S'){
            fprintf(output, 'Jerry went to the South');
        }
        if(JerryDirections[j] == 'W'){
            fprintf(output, 'Jerry went to the West');
        }
        if(JerryDirections[j] == 'E'){
            fprintf(output, 'Jerry went to the East');
        }
    }
    strcpy(c, "recursive_labryinth");
    strcat(c, ".out");
    output = fopen(c ,"w");

    for(int i = 0; i < rows; i++){
        for(int j = 0; j < cols; j++){
            fprintf(output, "%c", maze[i][j]);
        }
    }
    fclose(output);
}





