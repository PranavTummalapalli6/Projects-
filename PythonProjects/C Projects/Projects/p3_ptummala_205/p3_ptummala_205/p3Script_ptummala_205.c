Script started on 2023-05-02 23:37:06-04:00
bash-4.4$ unam[K[K[K[Kdate
Tue May  2 23:37:13 EDT 2023
bash-4.4$ uname -a
Linux zeus-1.cec.gmu.edu 4.18.0-348.23.1.el8_5.x86_64 #1 SMP Tue Apr 12 11:20:32 EDT 2022 x86_64 x86_64 x86_64 GNU/Linux
bash-4.4$ pwd
/home/ptummala/CS262/p3_ptummala_205
bash-4.4$ ls
driver.py  fork.c  fork.h  p3_ptummala_205.c  p3Script_ptummala_205.c  shell.c
bash-4.4$ lspwduname -a[4Pdatetar cvf lab10_ptummala_205.tar lab10_ptummala_205[C[C[C[C[C[C[C[C[C[Ccd ..[Ktar cvf lab10_ptummala_205.tar lab10_ptummala_205[C[C[C[C[C[C[C[C[C[C[16Pscript lab10Script_ptummala_205.c[C[C[C[C[C[C[C[C[C[C[7Plab10Script_ptummala_205.c[C[C[C[C[C[C[C[C[C[C[Cs[Kvim makefile[C[C[C[C[C[C[C[C[C[Cls[Kvim makefile[C[C[C[C[C[C[C[C[C[Cls[Kab10Script_ptummala_205.c[C[C[C[C[C[C[C[C[C[Cscript lab10Script_ptummala_205.c[C[C[C[C[C[C[C[C[C[Ctar cvf lab10_ptummala_205.tar lab10_ptummala_205[C[C[C[C[C[C[C[C[C[Ccd ..[Ktar cvf lab10_ptummala_205.tar lab10_ptummala_205[C[C[C[C[C[C[C[C[C[Cdate[Kuname -a[5Ppwd[1Pls[Kgcc p3_ptummala_205.c -o p3
/tmp/ccyIXzWb.o: In function `main':
p3_ptummala_205.c:(.text+0x1ed): undefined reference to `call_exe'
collect2: error: ld returned 1 exit status
bash-4.4$ cat p3_ptummala_205.c
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
bash-4.4$ exit
exit

Script done on 2023-05-02 23:38:18-04:00
