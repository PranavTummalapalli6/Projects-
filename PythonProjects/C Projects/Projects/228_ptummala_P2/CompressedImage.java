public class CompressedImage{
    private Tile[] tileArray;
    private int width;
    private int height;
    private boolean grayscale;
    private int x;
    private int y;
    private Pixel p;

    public CompressedImage(int height, int width, boolean grayscale){
        this.height = height;
        this.width = width;
        this.grayscale = grayscale;
        CompressedImage CImage  = new CompressedImage(this.width, this.height,this.grayscale);
    }
    public int getWidth(){
        return this.width;
    }
    public int getHeight(){
        return this.height;
    }
    public CompressedImage getPixel(int y, int x){
        //dont know
        return null;
    }

    public void setPixel(int y, int x, Pixel p){
        this.y = y;
        this.x = x;
        this.p = p;
    }
    public boolean equals(Object other){
        return false;
    }
}