import java.util.Scanner;
public class Image{
    private Tile[] tileArray;
    private int width;
    private int height;
    private boolean grayscale;
    private int x;
    private int y;
    private Pixel p;

    public Image(int height, int width, boolean grayscale){
       
        this.grayscale = grayscale;
        this.height = height;
        this.width = width;
        Image Image = new Image(this.width, this.height,this.grayscale);
        
    }
    public Image(String filename){
        Scanner scan = new Scanner(filename);
        while(scan.hasNextLine()){
            if(filename.contains("P2") == true){
                //find the grayscale value and assign it to this.grayscale = 

                this.grayscale = true;//read grayscal from file
            }
            else if(filename.contains("P3") == true){
                //constructs a color image
                this.grayscale = false;
            }
        }
    }
    public Image clone(){
        //return new Image(tileArray[]);
        return null;
    }
    public int getWidth(){
        return this.width;
    }
    public int getHeight(){
        return this.height;
    }
    public Image getPixel(int y, int x){
        return null;
        //using the coordinates to find the correlated tile and pixel
    }
    public void setPixel(int y, int x, Pixel p){
        this.y = y;
        this.x = x;
        this.p = p;
    
    }
    public Image scale(int factor){
        return null;
    }
    public Image crop(int topY, int topX, int height, int width){
        return null;
    }
    public Image flip(String direction){
        return null;
    }
    public Image rotate(boolean clockwise){
        return null;
    }
    public CompressedImage compress(boolean tileCompression, boolean pixelCompression){
        return null;
    }
    public boolean equals(Object other){
        return false;
    }
    
}