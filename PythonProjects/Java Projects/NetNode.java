/**
 *  This class has code that provides the basics for NetNode processes for the rest of the code.
 *
 * @author Pranav Tummalapalli
 */
public class NetNode {
    /**
     * private instance variable of the id of the node.
     */
    private int id;
    /**
     * private instance variable of the name of the node.
     */
    private String name;
    /**
     * private instance variable of the xcordinate of the node.
     */
    private double x_coordinate;
    /**
     * private instance variable of the ycordinate of the node.
     */
    private double y_coordinate;

    /** Netnode constructor.
     *
     * @param id the unique identification of the node.
     * @param name the name of the node.
     * @param x_coordinate the xcordintate of the node.
     * @param y_coordinate the ycordinate of the node.
     */
    public NetNode(int id,String name,double x_coordinate,double y_coordinate){
        this.id=id;
        this.name=name;
        this.x_coordinate=x_coordinate;
        this.y_coordinate=y_coordinate;  
    }

    /** setId setter for Id.
     *
     * @param id the unique identification of the node.
     */
    public void setId(int id){
        this.id=id;
    }
    /** setname setter for name.
     *
     * @param name the  name of the node.
     */
    public void setName(String name){
        this.name=name;
    }
    /** setxcordinate setter for xcordinate.
     *
     * @param x_coordinate the x coordinate of the node.
     */
    public void setX_coordinate(double x_coordinate){
        this.x_coordinate=x_coordinate;
    }
    /** setycordinate setter for ycordintae.
     *
     * @param y_coordinate the y coordinate of the node.
     */
     public void setY_coordinate(double y_coordinate){
        this.y_coordinate=y_coordinate;
    }
    /** getId getter for Id.
     *
     * @return id the unique identification of the node.
     */
    public int getId(){
        return id;
    }
    /** getName getter for name.
     *
     * @return name the name of the node.
     */
    public String getName(){
        return name;
    }
    /** getX_coordinate getter for X_coordinate.
     *
     * @return x_coordinate the x coordinate of the node.
     */
    public double getX_coordinate(){
        return x_coordinate;
    }
    /** gety_coordinate getter for ycoordinate.
     *
     * @return y_coordinate the y coordinate of the node.
     */
     public double getY_coordinate(){
        return y_coordinate;
    }
 }
