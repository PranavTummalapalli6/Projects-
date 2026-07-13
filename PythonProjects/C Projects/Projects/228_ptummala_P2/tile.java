public class Tile{
    private Pixel[] block;
    private int x;
    private int y;
    private Pixel p;
    
    public Tile(){
        this.block = new Pixel[16];
    }

    public Pixel getPixel(int y, int x){
        return(block[(int)(Math.sqrt(block.length) * (y + 1)) - 1 - (int) (Math.abs(y - x))]);
        
    }
    public void setPixel(int y, int x, Pixel p){
        this.y = y;
        this.x = x;
        this.p = p;
    }
    public boolean equals(Object other){
        Tile a = (Tile) other;
        if((a.block[0] == this.block[0]) && (a.block[1] == this.block[1]) && (a.block[2] == this.block[2]) && (a.block[3] == this.block[3]) && (a.block[4] == this.block[4]) && (a.block[5] == this.block[5]) && (a.block[6] == this.block[6]) && (a.block[7] == this.block[7]) && (a.block[8] == this.block[8]) && (a.block[9] == this.block[9]) && (a.block[10] == this.block[10]) && (a.block[11] == this.block[11]) && (a.block[12] == this.block[12]) && (a.block[13] == this.block[13]) && (a.block[14] == this.block[14]) && (a.block[15] == this.block[15])){//continue to idex 15
            return true;
    }
    return false;
}
    public String toString(){
        //return Integer.toString(block[0]) + "," + Integer.toString(block[1]) + "," + Integer.toString(block[2]);//continue to 15
        return null;
    }
    public Tile clone(){
        //return new Tile(block[15]);
        return null;
    }
}