#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fork.h"
#include <unistd.h>
#include <wait.h>
#include <errno.h>

#define MAX_ARGS 127

void printPrompt() {
    printf("262$ ");
    fflush(stdout); 
    
}


void concatCommand(char *input, Command *command) {
    
    memset(command, 0, sizeof(Command));
    
    
    char *token = strtok(input, " ");
    int i = 0;
    
    while (token != NULL) {
        if (i == 0) {
            strcpy(command->command, token);
        } 
        else if(i == MAX_ARGS){
            printf("error: too many arguments\n");
        }
        else {
            strcpy(command->arguments[i-1], token);
        }
        
        token = strtok(NULL, " ");
        i++;
    }
    
    command->arguments[i-1] = NULL;
}

int main() {
    char input[256]; 
    Command inputCommand; 

    while (1) {

        printPrompt();

        if (fgets(input, sizeof(input), stdin) == NULL) {
            
            printf("\n");
            break;
        }

        
        input[strcspn(input, "\n")] = '\0';
        concatCommand(input, &inputCommand);

        
        if (inputCommand.arguments[MAX_ARGS-1] != NULL) {
            fprintf(stderr, "Error: too many arguments\n");
            continue;
        }

        
        if (inputCommand.command == "exit") {
            printf("Exiting shell...\n");
            break;
        }

        pid_t pid = fork();

        if (pid == 0) {
            int result = call_exe(&inputCommand);

            if (result != 0) {
                fprintf(stderr, "Error: %s\n", strerror(result));
                exit(1);
            }

            exit(EXIT_FAILURE);
        } 
        else if (pid < 0) {
            fprintf(stderr, "Error: Fork Failed\n");
            continue;
        } 
        else {
            int status;
            waitpid(pid, &status, 0);
        }
    }

    return 0;
}
