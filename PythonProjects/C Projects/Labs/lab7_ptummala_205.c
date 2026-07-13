#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {

if (argc != 3) {

printf("Too many arguments or too few");

exit(1);

}

FILE *input_file = fopen(argv[1], "r");
FILE *output_file = fopen(argv[2], "w");


char customer_name[256];
char account_number[256];
char report_date[256];

fgets(customer_name, 256, input_file);
fgets(account_number, 256, input_file);
fgets(report_date, 256, input_file);

customer_name[strcspn(customer_name, "\n")] = '\0';
account_number[strcspn(account_number, "\n")] = '\0';
report_date[strcspn(report_date, "\n")] = '\0';

/*int a = customer_name[strcspn(customer_name, "\t")];
for(int i = a; i > strlen(customer_name); i++){
    *customer_name += customer_name[i];
}


int b = account_number[strcspn(account_number, "\t")];
for(int i = b; i > strlen(account_number); i++){
    *account_number += account_number[i];
}

int c = report_date[strcspn(report_date, 0)];
for(int i = c; i > strlen(report_date); i++){
    *report_date += report_date[i];
}*/

fprintf(output_file, "Customer: %s\n", customer_name);
fprintf(output_file, "Account: %s\n", account_number);
fprintf(output_file, "Reporting Date: %s\n", report_date);
fprintf(output_file, "Stock\t\tOpen Price\tClose Price\tLoss/Gain\n");

 
char stock_name[256];
int shares_held;
float opening_price;
float  high_price;
float  low_price;
float closing_price;
float change;

while (fgets(stock_name, 256, input_file) != NULL) {
sscanf(stock_name, "%s | Shares Held | %d | Opening Price | %f | High Price | %f | Low Price | %f | Closing Price | %f",
stock_name, &shares_held, &opening_price, &high_price, &low_price, &closing_price);
change = shares_held * (closing_price - opening_price);
fprintf(output_file, "%-10s\t%-15.2f\t%-15.2f\t", stock_name, opening_price, closing_price);

if (change < 0) {

fprintf(output_file, "-%.2f\n", -change);

} else {

fprintf(output_file, "%.2f\n", change);

}

}


fclose(input_file);

fclose(output_file);

return 0;

}
