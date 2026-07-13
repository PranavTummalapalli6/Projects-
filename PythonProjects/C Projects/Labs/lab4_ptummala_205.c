#include <stdio.h>

int hasRepeatedDigits(int num) {
int sum = 0;
int c[20];
int j = 0;
int count = 0;
while(num > 0){
    
	int lastDigit = num % 10;
	c[j++] = lastDigit;
	num /= 10;
    count += 1;


}
for(int i = 0; i < count; i++){
	for(int j = i + 1; j < count; j++){
		if(c[i] == c[j]){
			sum += 1;
		}
		
	}
	
}
return sum;

}

int printValidNumbers(int lower, int upper) {
    int count = 0; 

    for (int num = lower; num <= upper; num++) {
        if (!(hasRepeatedDigits(num) >= 1)) { 
            printf("%d\n", num); 
            count++; 
        }
    }

    return count; 
}


int main() {
    int lower;
    int upper;

    do {
        printf("Enter the lower bound A [1-5000]: ");
        scanf("%d", &lower);

        printf("Enter the upper bound B [1-5000]: ");
        scanf("%d", &upper);

        if (lower >= upper) {
            printf("Error! Make sure A<=B\n");
        } else if (lower < 1 || upper > 5000) {
            printf("Error! A and B must be between 1 and 5000\n");
        }
    } while (lower > upper || lower < 1 || upper > 5000);

    int count = printValidNumbers(lower, upper);
    printf("%d\n", count);

    return 0;
}
