package Coding_Summer;

public class NumberProcessor {
	/**
	*
	* This method returns
	*
	*
	*/
	public static int mirrorNumber(int input){
        int reversed = 0;
        int count = 0;
        int temp = input;
        
        while(temp != 0){
            temp = temp / 10;
            count += 1;
        }
        
        while(input != 0) {
            int digit = input % 10;
            input = input / 10;
            reversed += digit * Math.pow(10,count - 1);
            count -= 1;
          }
       return(reversed);
        //System.out.println(digit);
        
    }

	/**
	*
	* This method returns
	*
	*
	*/
	public static int stripOdds(int input) {
	    
        int digit;
        int zero = 0;
        int i = 1;
      
        while (input != 0)
        {
            digit = input % 10;
            input = input / 10;
            if (digit % 2 == 0)
                {
                    zero += digit * i;
                    i *= 10;
                }
      }
      
      return(zero);
    }
	

	/**
	*
	* This method returns
	*
	*
	*/
	public static boolean hasHiddenPrime(long input) {//change strings to arrays//if statement to see if whole number is prime//check to see if individual digits are prime 
        

        if(input == 0 || input == 1 || input == 2 || input == 3) //base case to handle 0,1,2,3
        return false;
      
        else
      {
          while( input / 10 != 0 && !checkPrime(input) ) // !checkPrime is for 2-digit
          {
              input = input / 10; //take off each digit and check if remaining is prime
              if( checkPrime(input) )
                return true;
          }
          return false;
      }
  }
  //function to check if number is prime
  public static boolean checkPrime(long input2){
  
    boolean flag = false;//counter
    int count = 0;
    int temp = (int)input2;
    while (temp > 0) {
    temp = temp / 10;
    count++;
    }
    

    for (int j = 2; j >= input2 / 2; j--){
      
      if (input2 % j == 0){
        flag = true;
        break;
      }
  flag = false;
}
return(flag);

    
}
  

    // condition for nonprime number
   


	/**
	*
	* This method returns true if
	*
	*
	*/
	public static boolean isCozyNumber(int input1, int input2) {
		// if int 2 is in int1 
        int flig = 0;
        boolean flag = true;
        int digit;
        int unit;
        int temp = input1;
        int temp2 = input2;
        int count = 0;
        int count2 = 0;
        int finalcount1, finalcount2;
        int[] array;
        
        int[] arr;
    
          if(input1 < input2){
              flag = false;
    
          }
          
          else if(input1 == input2){
              flag = true;
          }
          else if(input1 > input2){
              
              while (temp > 0) {
                  temp = temp / 10;
                  count++;
                  }
                  finalcount1 = count;
                  arr = new int[count];
                  
  
              while (temp2 > 0) {
                  temp2 = temp2/ 10;
                  count2++;
                  }
                  finalcount2 = count2;
                  array = new int[count2];
              while(input1 != 0){
  
                  digit = input1 % 10;
                  input1 = input1 / 10;
                  arr[--finalcount1] = digit;
   
              }
             
              
              while(input2 != 0){
                  
                  unit = input2 % 10;
                  input2 = input2 / 10;
                  array[--finalcount2] = unit;
       
              }
  
              for(int j = 0; j < count; j++){
                      if(array[0] == arr[j]){
                          
                          flig = j;
                          break;
                      }
   
                  
              }
              for(int k = 0; k < count2; k++){
                  if(array[k] != arr[k + flig]){
                      flag = false;
                  }
                  
              }
              
               
          }
          
          return(flag); 
      }

	/**
	 *
	 * This method returns true if
	 *
	 */
	public static boolean isNumberJackWinner(int[] array){
		
    boolean flag = false;
    if(array.length < 3 || array.length > 3){
      flag = false;
  }

  int sum = 0;
  for(int i = 0; i < array.length; i++){
      sum += array[i];
      if(17 <= sum && sum <= 21 && array[i] >= 1 && array[i] <= 10 ){
        flag = true;
    }
    else{
        flag = false;
    }
    
  }
  return flag;
  
} 

	/**
	 *
	 * This method returns
	 *
	 */
	public static int[][] array2matrix(int[] array){
		
        int index = 0;
	    int l = 2;
        int len = array.length;
        int rows = array[index];
	    int cols = array[index + 1];
	    int[][] array2matrix = new int[rows][cols];
	    for(int i = 0; i < rows; i++){
            if(len <= l){
                break;
              }
	        for(int j = 0; j < cols; j++){
	            array2matrix[i][j] = array[l++];
	        }
	    }
	    return array2matrix;
    }

	

	/**
	 * This methods returns
	 */
	 public static void shootBattleCraft(int[][] battleMap, int[][] shotCoordinates) {
		for( int i = 0; i < shotCoordinates.length; i++){
            if(battleMap [shotCoordinates[i][0]] [shotCoordinates[0][i]]!= 0){
                battleMap[shotCoordinates[0][i]] [shotCoordinates[0][i]] = -1;
            }

        }
        
	}

	/**
	 *
	 * Main method. Is not tested by the tester, create your own tests here!
	 */
	public static void main(String[] args){
		//pass
	}

}
