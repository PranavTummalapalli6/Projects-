#include <stdio.h>
#include <stdlib.h>

struct Node {
    int randInt;
    struct Node* next;
};

void insertNodeSorted(struct Node ** head, struct Node * prevNode){
    struct Node * tempNode;
    if(*head == NULL || (*head)->randInt >= prevNode->randInt){
        prevNode->next = *head;
        *head = prevNode;
    }
    else{
        tempNode = *head;
        while(tempNode->next != NULL && tempNode->next->randInt < prevNode->randInt){
            tempNode = tempNode->next;
        }
        prevNode->next = tempNode->next;
        tempNode->next = prevNode;
    }
}

void printList(struct Node * head){
    printf("The sorted Linked List is: \n");
    struct Node * temp = head;
    while(temp != NULL){
        printf("%d", temp->randInt);
        temp = temp->next;
    }
    printf("\n");
}
void deleteList(struct Node** head){
    struct Node * temp = *head;
    struct Node * next;
    
    while(temp != NULL){
    next = temp->next;
    free(temp);
    temp = next;
    }
    *head = NULL;
}

struct Node *createNode(int randValue)
{
struct Node* newNode = (struct Node*) malloc(sizeof(struct Node));
newNode->randInt = randValue;
newNode->next = NULL;

return newNode;
}

int main(int argc, char * argv[]){
    char * SortedLinkedList;
    int numOfRands;
    int randSeed;
    int Max_val;

    
    SortedLinkedList = argv[0];
    printf("Program Name: %s\n", SortedLinkedList);

    if(atoi(argv[1]) < 0){
        EXIT_FAILURE;
    }
    randSeed = atoi(argv[1]);
    printf("The random Seed is: %d\n", randSeed);

    if(atoi(argv[2]) < 0){
        EXIT_FAILURE;
    }
    numOfRands = atoi(argv[2]);
    printf("The number of random numbers are: %d\n", numOfRands);

    if(atoi(argv[3]) < 0){
        EXIT_FAILURE;
    }
    Max_val = atoi(argv[3]);
    printf("The max value of the random values are: %d\n", Max_val);

    struct Node* headNode = NULL;
    struct Node *prevNode;
    srand(randSeed);

    for (int i = 1; i <= numOfRands; i++)
    {
    int rand_num = rand() % Max_val + 1;
    printf("The random number generated was: %d\n", rand_num);
    prevNode = createNode(rand_num);
    insertNodeSorted(&headNode, prevNode);
}

printList(headNode);
deleteList(&headNode);
return 0;
}
