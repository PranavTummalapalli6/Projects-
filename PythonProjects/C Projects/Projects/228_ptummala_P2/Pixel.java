public class Pixel{

    private int[] value;
    
    public Pixel(int grayvalue){
        value = new int[1];
        value[0] = grayvalue;
    }
    public Pixel(int red, int green, int blue){
        value = new int[3];
        value[0] = red;
        value[1] = blue;
        value[2] = green;
    }
    public int[] getValue(){
        return value;
    }
    public boolean equals(Object other){
        boolean flag = false;
        if(other instanceof Pixel){
            Pixel a = (Pixel) other;
            if(a.value[0] == this.value[0] && a.value[1] == this.value[1] && a.value[2] == this.value[2]){
                flag = true;
            }
           flag = false;     
        }
        return flag;
    }
    public String toString(){
        String a = "";
        if(value.length == 1){
            a += (Integer.toString(value[0]));

        }
        else if(value.length == 3){
            a += ("R" + Integer.toString(value[0]) + "#G" + Integer.toString(value[1]) + "#B" + Integer.toString(value[2]));
        }
        return a;
    }
    public Pixel clone(){
        if(value.length == 1){
            return (new Pixel(value[0]));
        }
        else{
            return (new Pixel(value[3]));
        }
    }
}