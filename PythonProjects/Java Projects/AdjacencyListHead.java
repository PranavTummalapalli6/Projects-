import java.util.*;
/**
 *  This class has code that provides AdjacencylistHead code that that provides the adjacency List and
 *  multiple key methods used in NetGraph and NetNode.
 *
 * @author Pranav Tummalapalli
 */
public class AdjacencyListHead {
    /**
     * stores private NetNode instance variable.
     */
    private NetNode node;
    /**
     * instantiates the LinkedList adjacancyList that acts as the list for the graph.
     */
    private LinkedList<Adjacent> adjacencyList;

    /** Constructor Method AdjacecncyListHead that instantiates the node and the adjacencyList a LinkedList of type Adjacent.
     *
     * @param node of type NetNode that is crucial to the node of the graph.
     *
     *
     */
    public AdjacencyListHead(NetNode node){
        this.node=node;
        this.adjacencyList=new LinkedList<Adjacent>();
    }
    /** Another Constructor of the AdjacencyListHead class with the parameters node and adjacency List.
     *
     * @param node of type NetNode that is crucial to the node of the graph.
     * @param adjacencyList of type LinkedList from the Adjacent class.
     *
     *
     */
    public AdjacencyListHead(NetNode node,LinkedList<Adjacent> adjacencyList){
        this.node=node;
        this.adjacencyList=adjacencyList;
    }
    /** setNetNode method that acts as a setter for the Node.
     *
     * @param node  of type NetNode that is crucial to the node of the graph.
     *
     */
    public void setNetNode(NetNode node){
        this.node=node;
    }
    /** setAdjacencyList method that acts as a setter of the Adjacency List.
     *
     * @param adjacencyList of type Adjacent that is a Linked List.
     *
     */
    public void setAdjacencyList(LinkedList<Adjacent> adjacencyList){
        this.adjacencyList=adjacencyList;
    }
    /** getNetNode method that is a getter method that return node.
     *
     * @return node of type NetNode that is crucial to the node of the graph.
     *
     */
    public NetNode getNetNode(){
        return node;
    }
    /** getAdjacencyList method that is a getter method that returns adjacency List.
     *
     * @return adjacencyList of type Adjacent that returns the linked List of adjacent edges to the node.
     *
     */
    public LinkedList<Adjacent> getAdjacencyList(){
        return adjacencyList;
    }
    
    
}
