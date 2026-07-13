/* This is the only file you will be editing.
 * - otur_sched.c (Otur Scheduler Library Code)
 * - Copyright of Starter Code: Prof. Kevin Andrea, George Mason University. All Rights Reserved
 * - Copyright of Student Code: You!  
 * - Copyright of ASCII Art: Modified from Joan Stark (jgs)'s work:
 * -- https://www.asciiart.eu/animals/other-water
 * - Restrictions on Student Code: Do not post your code on any public site (eg. Github).
 * -- Feel free to post your code on a PRIVATE Github and give interviewers access to it.
 * -- You are liable for the protection of your code from others.
 * - Date: Aug 2024
 */

/* CS367 Project 1, Spring Semester, 2024
 * Fill in your Name, GNumber, and Section Number in the following comment fields
 * Name:Pranav Tummalapalli
 * GNumber:G01323137
 * Section Number: CS367-004             (Replace the _ with your section number)
 */

/* otur CPU Scheduling Library
  .-"""-.
 /      o\
|    o   0).-.
|       .-;(_/         .-.
 \     /  /)).-------._|  `\   ,
  '.  '  /((           `'-./ _/|
    \  .'  )    OTUR    .-.;`  /
     '.                 |  `\-'
       '._            -'    /
 jgs      ``""------`------`
*/
 
/* Standard Library Includes */
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
/* Unix System Includes */
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <pthread.h>
#include <sched.h>
/* Local Includes */
#include "otur_sched.h"
#include "vm_support.h"
#include "vm_process.h"

/* Feel free to create any helper functions you like! */

/*** Otur Library API Functions to Complete ***/

/* Initializes the Otur_schedule_s Struct and all of the Otur_queue_s Structs
 * Follow the project documentation for this function.
 * Returns a pointer to the new Otur_schedule_s or NULL on any error.
 * - Hint: What does malloc return on an error?
 */
  
Otur_schedule_s *otur_initialize() {

  Otur_schedule_s* sched = calloc (1, sizeof(Otur_schedule_s)); //allocating space for the pointer to the schedule struct
  sched->ready_queue_high = (Otur_queue_s*) calloc (1, sizeof(Otur_queue_s)); //allocating space for the high priority queue
  sched->ready_queue_normal = (Otur_queue_s*) calloc (1, sizeof(Otur_queue_s)); //allocating space for the normal priority queue
  sched->defunct_queue = (Otur_queue_s*) calloc (1, sizeof(Otur_queue_s)); // allocating space for the defunct queue using calloc and explicit type casting

  sched->ready_queue_high->head = NULL; // set default value for the head to be NULL
  sched->ready_queue_high->count = 0; // set default value for the count of queue to be 0
  sched->ready_queue_normal->head = NULL;
  sched->ready_queue_normal->count = 0;
  sched->defunct_queue->head = NULL;
  sched->defunct_queue->count = 0;

  return sched;// returns the pointer to the schedule struct

}

/* Allocate and Initialize a new Otur_process_s with the given information.
 * - Malloc and copy the command string, don't just assign it!
 * Follow the project documentation for this function.
 * - You may assume all arguments are Legal and Correct for this Function Only
 * Returns a pointer to the Otur_process_s on success or a NULL on any error.
 */
Otur_process_s *otur_invoke(pid_t pid, int is_high, int is_critical, char *command) {

  Otur_process_s *process = (Otur_process_s*) calloc(1, sizeof(Otur_process_s)); //returns pointer to the process struct
  unsigned short mask = 1 << 13;//creates a mask with 1 at the 13th bit
  process->state |= mask; //combines the mask with the process state to set the state member to 1
  unsigned short mask1 = 1 << 12; //creates a mask with 1 at the 12th bit
  unsigned short mask2 = 1 << 14; //creates a mask with 1 at the 14th bit 
  process->state &= ~mask1; // combines the mask with the process state to set the runnin state member to 0
  process->state &= ~mask2; // comnines the mask with the process state to set the defunct state member to 0

if(is_critical == 0){//conditional to see if the process is critical or not
  unsigned short mask3 = 1 << 11;//if it is creates a mask with 1 at the 11th bit
  process->state &= ~mask3; //combines the process state with the negation of the bit to set critical bit to 0
}
else{
  unsigned short mask4 = 1 << 11; //creates a mask with a 1 at the 11th bit
  process->state |= mask4; //setting critical bit to 1
  unsigned short mask5 = 1 << 15; //creates a mask with a 1 at the 15 bit
  process->state |= mask5;//setting high bit to 1
}
if(is_high == 0){ //conditional to see if the process is high priority task or not
  unsigned short mask6 = 1 << 15;//creates a mask
  process->state &= ~mask6;//assigns the high bit to 0
}
else{
  unsigned short mask7 = 1 << 15;//creates a mask
  process->state |= mask7;//assigns high bit to 1
}
unsigned short mask8 = 1 << 0;//creates a mask with 1 at the 0 bit
unsigned short mask9 = 1 << 1;//creates a mask with 1 at the 1 bit
unsigned short mask10 = 1 << 2;//creates a mask with 1 at the 2 bit
unsigned short mask11 = 1 << 3;//creates a mask with 1 at the 3 bit
unsigned short mask12 = 1 << 4;//creates a mask with 1 at the 4 bit
unsigned short mask13 = 1 << 5;//creates a mask with 1 at the 5 bit
unsigned short mask14 = 1 << 6;//creates a mask with 1 at the 6 bit
unsigned short mask15 = 1 << 7;//creates a mask with 1 at the 7 bit
process->state &= ~mask8; //creates a process to set the lower 8 bits to all 0's
process->state &= ~mask9;
process->state &= ~mask10;
process->state &= ~mask11;
process->state &= ~mask12;
process->state &= ~mask13;
process->state &= ~mask14;
process->state &= ~mask15;
process->age = 0; //Initializes age to 0
process->cmd = calloc(strlen(command) + 1, sizeof(char));//allocating dynamic memory for the cdm command
strncpy(process->cmd, command, strlen(command) + 1);// copying the command fromt he parameter to the process's cmd
process->next = NULL;//Initializing the next process to null

if(process == NULL){//null check if there are potential errors
  return NULL;
}
return process;

}

/* Inserts a process into the appropriate Ready Queue (singly linked lists).
 * Follow the project documentation for this function.
 * - Do not create a new process to insert, insert the SAME process passed in.
 * Returns a 0 on success or a -1 on any error.
 */
int otur_enqueue(Otur_schedule_s *schedule, Otur_process_s *process) {

  if(schedule == NULL || process == NULL){//null check if schedule or process are null to return -1 (failure)
    return -1;
  }
  unsigned short masky = 1 << 13; 
  process->state |= masky;//setting the ready state bit to 1 and setting the defunct and running bits to 0
  unsigned short masky1 = 1 << 12;
  unsigned short masky2 = 1 << 14;
  process->state &= ~masky1;
  process->state &= ~masky2;
  unsigned short masky3 = 1 << 15;
  unsigned short result = process->state & masky3; //putting the binary value of the critical bit into the variable result
  unsigned short masky4 = 1 << 11;
  unsigned short result1 = process->state & masky4;//putting the binary calue of the critical bit into the variable result

  Otur_process_s *current; //declaring current pointer
  Otur_process_s *temp; //declaring temp pointer


  int count = 1;//setting int count variable to 1
  int count2 = 1;//setting int count variable to 1

  if(result || result1){//binary condition to see if either the high or critical bit is True or False
    if(schedule->ready_queue_high->head == NULL){//conditional to see if the high priority queue is null
      schedule->ready_queue_high->head = process;//sets the high priority queue head equal to the process given
      schedule->ready_queue_high->count = 1; // then sets the count of hte queue = 1
    }
    else{ //when there are processes in the queue
      temp = schedule->ready_queue_high->head; //initializes the temp pointer to the head of the high prioriry queue
      while(temp->next != NULL){//while loop to iterate through all the nodes until temp's next node is NULL
      temp = temp->next;
      count++;//incremenets count
      }
      temp->next = process;//sets the next of the last node to the process
      schedule->ready_queue_high->count = count + 1;//increments count
    }
  }
  else{ //when the critical or high bit is not TRUE so process must be added ot normal queue
    if(schedule->ready_queue_normal->head == NULL){ //conditional to see if normal queue is empty
      schedule->ready_queue_normal->head = process; //adds process ot the queue
      schedule->ready_queue_normal->count = 1; // increments count
    }
    else{ //when the normal queue is not empty 
      current = schedule->ready_queue_normal->head; //sets the current pointer to the head of the normal queue
      while(current->next != NULL){ //while loop to iterate through all the nodes of the normal queue until the last node is reached and also icrement ccount
      current = current->next;
      count2++;
      }
      current->next = process; //the next node of the last node is assigned to process, processs is added to normal queue
      schedule->ready_queue_normal->count = count2 + 1; // count is initialized
    }
  }
  return 0;
}


/* Returns the number of items in a given Otur Queue (singly linked list).
 * Follow the project documentation for this function.
 * Returns the number of processes in the list or -1 on any errors.
 */
int otur_count(Otur_queue_s *queue) {
  if(queue == NULL){//conditional to see if the queue is NULL, when it is not return the count of the queue
    return -1;
  }
  return queue->count;
  
}

/* Selects the best process to run from the Ready Queue (singly linked list).
 * Follow the project documentation for this function.
 * Returns a pointer to the process selected or NULL if none available or on any errors.
 * - Do not create a new process to return, return a pointer to the SAME process selected.
 */
Otur_process_s *otur_select(Otur_schedule_s *schedule) {
  if(schedule == NULL){//null case to see if schedule is null 
    return NULL;
  }

  Otur_process_s *prev;// declaring pointers to the process struct
  Otur_process_s *current;
  Otur_process_s *temp1;
  Otur_process_s *temp;

  if(schedule->ready_queue_high->head != NULL){//null check to see if the queue is null or not
    current = schedule->ready_queue_high->head;//initializing all the pointers to the head of the high prioriry queue
    prev = schedule->ready_queue_high->head;
    while(current->next != NULL){//while loop to iterate through all the nodes in the queue
       unsigned short maks = 1 << 11;
        current->state &= ~maks;//set the critical bit to 1
      if(current->state >> 11 != 0){// conditiaonal to see if the critical bit is 1
        prev->next = prev->next->next;//deletes the current node
        current->age = 0;//initializes age
        unsigned short masky = 1 << 13;
        current->state |= masky;//sets the running bit to 1
        unsigned short masky1 = 1 << 12;
        unsigned short masky2 = 1 << 14;
        current->state &= ~masky1;
        current->state &= ~masky2;//sets the ready, defucnt bit to 0 
        current->next = NULL;
        return current;
      }
      else{
        prev = current;
        current = current->next; 
      }
    }
  }

  else if(schedule->ready_queue_high != NULL && schedule->ready_queue_high->head != NULL){// if the queue is not null and the head is not null 
    temp = schedule->ready_queue_high->head;//set a pointer ot the nead
    temp->age = 0;//intializes age 
    unsigned short max = 1 << 13;
    temp->state |= max;
    unsigned short max1 = 1 << 12;
    unsigned short max2 = 1 << 14;
    temp->state &= ~max1;
    temp->state &= ~max2;//sets the bits
    temp->next = NULL;
    return temp;
  }
  
  else if(schedule->ready_queue_normal->head != NULL){//checks to see if the head of the normal queue is null
     temp1 = schedule->ready_queue_normal->head; //sets temp1 to the head 
     temp1->age = 0;//initializes age
     unsigned short maxy = 1 << 13;
     temp1->state |= maxy;
     unsigned short maxy1 = 1 << 12;
     unsigned short maxy2 = 1 << 14;
     temp1->state &= ~maxy1;
     temp1->state &= ~maxy2;//sets the bits
     temp1->next = NULL;
     return temp1;

  }
  return NULL;
}

/* Ages up all Process nodes in the Ready Queue - Normal and Promotes any that are Starving.
 * - If the Ready Queue - Normal is empty, return 0.  (Nothing to do, so it was a success)
 * Follow the project documentation for this function.
 * Returns a 0 on success or a -1 on any error.
 */
int otur_promote(Otur_schedule_s *schedule) {
  if(schedule->ready_queue_normal != NULL && schedule->ready_queue_high != NULL && schedule->ready_queue_high->head && schedule->ready_queue_normal->head){// null check 
    Otur_process_s *temp = schedule->ready_queue_normal->head;//pointers to the head of the respective queues
    Otur_process_s *prev = schedule->ready_queue_normal->head;
    Otur_process_s *temp2 = schedule->ready_queue_high->head;
    while(temp->next != NULL){//iterating thru all the nodes to increment the age and check if the age is starving in whihc case will be moved to normal queue
      temp->age += 1;//
      if(temp->age >= STARVING_AGE){
        prev->next = prev->next->next;//deleting node if age >= starcing age
        temp->next = NULL;
      }
      prev = temp;
      temp = temp->next;
    }
    while(temp2->next != NULL){//itearting thru the high prioriry queue
      temp2 = temp2->next;
    }
    temp2->next = temp;
  }
  else if(schedule->ready_queue_high == NULL && schedule->ready_queue_normal == NULL){//null check
    return -1;
  }
  return 0;
}

/* This is called when a process exits normally that was just Running.
 * Put the given node into the Defunct Queue and set the Exit Code into its state
 * - Do not create a new process to insert, insert the SAME process passed in.
 * Follow the project documentation for this function.
 * Returns a 0 on success or a -1 on any error.
 */
int otur_exited(Otur_schedule_s *schedule, Otur_process_s *process, int exit_code) {
  unsigned short maxi = 1 << 12;
  process->state |= maxi; //setting the defucnt state bit ot 1 
  unsigned short maxi1 = 1 << 13;
  unsigned short maxi2 = 1 << 14;
  process->state &= ~maxi1;
  process->state &= ~maxi2;//setting the other bits to 0
  process->state &= ~0xFF;
  process->state |= exit_code;//setting the state bits to the exit code
  Otur_process_s *temp = schedule->defunct_queue->head;
  if(temp != NULL){//null chekc
    while(temp->next != NULL){//iteraitng thru the defunct queue to find last node and add process to the end 
    temp = temp->next;
    }
    temp->next = process;
  }
  
  if(schedule->defunct_queue == NULL){//null chekc
    return -1;
  }
  return 0;
}

/* This is called when StrawHat kills a process early (kill command). 
 * - The Process will either be in your Ready or Suspended Queue, or neither.
 * - The difference with otur_exited is that this process is in one of your Queues already.
 * Remove the process with matching pid from the Ready or Suspended Queue and add the Exit Code to it.
 * - You have to check both since it could be in either queue.
 * Follow the project documentation for this function.
 * Returns a 0 on success or a -1 on any error (eg. process not found).
 */
int otur_killed(Otur_schedule_s *schedule, pid_t pid, int exit_code) {
  Otur_process_s *temp = schedule->ready_queue_high->head;//pointers to the head of the respective queues
  Otur_process_s *prev = schedule->ready_queue_high->head;
  Otur_process_s *current = schedule->ready_queue_normal->head;
  Otur_process_s *prev2 = schedule->ready_queue_normal->head;
  Otur_process_s *defunct = schedule->defunct_queue->head;
  if(schedule->ready_queue_high != NULL && temp != NULL && prev != NULL){//null check
    while(temp->next != NULL){//iterating thru all the nodes to delete the node when the pid matches the processes pid 
      if(temp->pid == pid){
        prev->next = prev->next->next;
        temp->next = NULL;
        unsigned short maxiu = 1 << 12;
        temp->state |= maxiu;
        unsigned short maxiu1 = 1 << 13;
        unsigned short maxiu2 = 1 << 14;
        temp->state &= ~maxiu1;
        temp->state &= ~maxiu2;//set the defunct state 
        temp->state &= ~0xFF;
        temp->state |= exit_code;//setting the bits to the exit code
      }
      prev = temp;
      temp = temp->next;
    }
    if(defunct != NULL){//null check
      while(defunct->next != NULL){//iteraitng defunct to find the last node and assigning it to temp
        defunct = defunct->next;
      }
      defunct->next = temp;
    }
  }
  else if(schedule->ready_queue_normal != NULL && current != NULL && prev2 != NULL){//null check
    while(current->next != NULL){//iterating current to find same pid and remove node
      if(current->pid == pid){
        prev2->next = prev2->next->next;
        current->next = NULL;
        unsigned short maxiua = 1 << 12;
        current->state |= maxiua;
        unsigned short maxiua1 = 1 << 13;
        unsigned short maxiua2 = 1 << 14;
        current->state &= ~maxiua1;//set defunct state
        current->state &= ~maxiua2;
        current->state &= ~0xFF;
        current->state |= exit_code;//setting bits to exit code
      }
      prev2 = temp;
      current = current->next;
    }
    if(defunct != NULL){//null chekc
     while(defunct->next != NULL){//finding last defunct node and adding process to the end
      defunct = defunct->next;
    }
    defunct->next = current;
    }
  }
  else{
    return -1;
  }
  return 0; 
}


/* This is called when the StrawHat reaps a Defunct process. (reap command)
 * Remove and free the process with matching pid from the Defunct Queue and return its exit code.
 * Follow the project documentation for this function.
 * Returns the process' exit code on success or a -1 if no such process or on any error.
 */
int otur_reap(Otur_schedule_s *schedule, pid_t pid) {
  Otur_process_s *temp = schedule->defunct_queue->head;//pointers to the head of the defucnt queue
  Otur_process_s *prev = schedule->defunct_queue->head;
  unsigned short maskyito = 0xFF;//mask that is all 1 for the first 7 bits
  unsigned short exit_code;
  
  if(schedule->defunct_queue != NULL && temp != NULL && prev != NULL){//null check
    while(temp->next != NULL){//iteraitng thru all the nodes in the defucnt queue to see if the pid mathces the process pid if that happens delete node
      if(temp->pid == pid){
        prev->next = prev->next->next;
        temp->next = NULL;
        return exit_code = temp->state & maskyito;// return the exit code of the process 
        free(temp);
      }
      else if(temp->pid == 0){//if pid equals 0
        schedule->defunct_queue->head = schedule->defunct_queue->head->next;//delete node
        schedule->defunct_queue->head->next = NULL;
        return exit_code = temp->state & maskyito;
        free(temp);
      }

      prev = temp;
      temp = temp->next;
    }
  
  }
  return -1;
}

/* Frees all allocated memory in the Otur_schedule_s, all of the Queues, and all of their Nodes.
 * Follow the project documentation for this function.
 * Returns void.
 */
void otur_cleanup(Otur_schedule_s *schedule) {
  Otur_process_s *temp = schedule->ready_queue_high->head; //all the pointers that point to the head of the queues
  Otur_process_s *current = schedule->ready_queue_normal->head;
  Otur_process_s *head = schedule->ready_queue_normal->head;
  Otur_process_s *head1 = schedule->ready_queue_high->head;
  Otur_process_s *head2 = schedule->defunct_queue->head;
  Otur_process_s *defunct = schedule->defunct_queue->head;
  
  if(temp != NULL && head1 != NULL){//null check to see if the heads of the queues are null
    while(temp->next != NULL){//iterate through all the nodes and free each node as well as cmd of each node
    head1 = temp;
    temp = temp->next;
    free(head1->cmd);
    free(head1);
    }
  }
  if(current != NULL && head != NULL){//null check to see if the heads of the queues are null
    while(current->next != NULL){//iterate through all the nodes and free each node as well as cmd of each node
    head = current;
    current = current->next;
    free(head->cmd);
    free(head);
    }
  }
  
  if(defunct != NULL && head2 != NULL){//null check to see if the heads of the queues are null
    while(defunct->next != NULL){//iterate through all the nodes and free each node as well as cmd of each node
    head2 = defunct;
    defunct = defunct->next;
    free(defunct->cmd);
    free(defunct);
    }
  }
  
  free(schedule->defunct_queue);//freeing all the queues and the schedule struct
  free(schedule->ready_queue_high);
  free(schedule->ready_queue_normal);
  free(schedule);
}