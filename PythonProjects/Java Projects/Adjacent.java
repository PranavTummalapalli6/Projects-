/**
 *  This class has code that provides the AdjacencyList and other AdjacencyListHead methods.
 *
 * @author Pranav Tummalapalli
 */
public class Adjacent {
    /**
     * private instance variable neighbor of type NetNode.
     */
    private NetNode neighbor;
    /**
     * private instance variable weight of type weight.
     */
    private double weight;
    /** Constructor of Adjacent Class with the parameters neighbor and weight.
     *
     * @param neighbor of type NetNode that identifies the next node.
     * @param weight  of type double that represents the numerical value of the length of the edge.
     *
     */
    public Adjacent(NetNode neighbor,double weight){
        this.neighbor=neighbor;
        this.weight=weight;
    }
    /** Setter method of setNeighbor Neighbor that sets the neighbor value with parameter of type NetNode neighbor.
     *
     * @param neighbor of type NetNode that identifies the next node.
     *
     */
    public void setNeighbor(NetNode neighbor){
       this.neighbor=neighbor; 
    }
    /** Setter method setWeight of Weight that sets the value of weight with parameter weight.
     *
     * @param weight of type double that represents the numerical value of the length of the edge.
     *
     */
    public void setWeight(double weight){
        this.weight=weight;
    }
    /** Getter method getNeighbor of neighbor that returns the value of neighbor.
     *
     * @return neighbor of type NetNode that identifies the next node.
     *
     */
     public NetNode getNeighbor(){
       return neighbor; 
    }
    /** Getter method getWeight of weight that returns the value of weight.
     *
     * @return weight of type double that represents the numerical value of the length of the edge.
     *
     */
    public double getWeight(){
        return weight;
    }  
} 
