import java.util.*;
/**
 *  This class has code that provides eventually leads to printing a graph with nodes and a combined LinkedList.
 *
 * @author Pranav Tummalapalli
 */
public class NetGraph {
    /**
     * private instance variable nodesList of type AdjacencyListHead that is an ArrayList.
     */
    private ArrayList<AdjacencyListHead> nodesList;

    /** Constuctor of the NetGraph class with nodesList as a parameter.
     *
     * @param nodesList of type AdjacencyListHead that is an ArrayList.
     */
    public NetGraph(ArrayList<AdjacencyListHead> nodesList){
        this.nodesList=nodesList;
    }

    /** Getter method of the NodesList.
     *
     * @return nodesList of type AdjacencyListHead that is an ArrayList.
     */
    public ArrayList<AdjacencyListHead> getNodesList(){
        return nodesList;
    }

    /**getNumNodes returns the amount of vertexes in the graph that means nodes.
     *
     * @return nodesList.size() returns the number of nodes or vertexes
     */
    public int getNumNodes(){
        return nodesList.size();
    }

    /**getNumLinks returns the number of edges in the graph.
     *
     * @return sum/2 that represents the number of edges in the graph.
     */
    public int getNumLinks(){
        int sum = 0;
        for(AdjacencyListHead node : nodesList){
            sum += node.getAdjacencyList().size();

        }
        return sum/2;
    }

    /**insertNetNode with the id, name, xcordinate, ycordinate, parameters throws Illegal argument exception if the node that needs to be inserted is already in the nodesList if not
     * adds the node.
     *
     * @param id the unique identification of the node.
     * @param name the name of the certain node.
     * @param x_coordinate the x position of the node.
     * @param y_coordinate the y position of the node.
     * @throws IllegalArgumentException exception that is thrown when the node is already in the nodesList.
     */
    public void insertNetNode(int id,String name,double x_coordinate,double y_coordinate) throws IllegalArgumentException
	{
        NetNode newNode = new NetNode(id, name, x_coordinate, y_coordinate);
        for(AdjacencyListHead node : nodesList){
            if(node.getNetNode().getId() == id){
                throw new IllegalArgumentException();
            }
        }
        nodesList.add(new AdjacencyListHead(newNode));
	}

    /** addLink method with parameters node1, node2, and weight with exception illegal argument when nodes are null or in NodesList.
     *
     * @param node1 first node to be linked.
     * @param node2 second node to be linked.
     * @param weight the distance between both of said nodes.
     * @throws IllegalArgumentException exception that is thrown when nodes are null or already in nodesList.
     */
    public void addLink(NetNode node1, NetNode node2, double weight) throws IllegalArgumentException{
       if(node1 == null || node2 == null){
           throw new IllegalArgumentException();
       }
        boolean flag = false;
        boolean galf = false;
       for(AdjacencyListHead node : nodesList){

           if(node.getNetNode().getId() == node1.getId()){
               flag = true;
           }
           if(node.getNetNode().getId() == node2.getId()){
               galf = true;
           }

       }
        if(!galf && !flag){
            throw new IllegalArgumentException();
        }
        for(AdjacencyListHead adjacentnode : nodesList) {
            if(adjacentnode.getNetNode().getId() == node1.getId()){
                for(Adjacent a:adjacentnode.getAdjacencyList()){
                    if(a.getNeighbor().getId()==node2.getId())return;
                    if(a.getNeighbor().getId()==node1.getId())return;
                }
            }
        }
        for(AdjacencyListHead adjNode : nodesList){
            if(adjNode.getNetNode().getId() == node1.getId()){
                Adjacent adjacentNode1 = new Adjacent(node2, weight);
                LinkedList<Adjacent> a = adjNode.getAdjacencyList();
                a.add(adjacentNode1);
                adjNode.setAdjacencyList(a);
            }
            if(adjNode.getNetNode().getId() == node2.getId()){
                Adjacent adjacentNode2 = new Adjacent(node1, weight);
                LinkedList<Adjacent> b = adjNode.getAdjacencyList();
                b.add(adjacentNode2);
                adjNode.setAdjacencyList(b);
            }


        }
    }

    /**deleteNetNode that deletes a certain node from the nodesList.
     *
     * @param node one of the nodes that make up the plenty in nodesList.
     * @throws IllegalArgumentException exception that is thrown when nodes are null or already in nodesList.
     */
    public void deleteNetNode(NetNode node)throws IllegalArgumentException{
        if(node == null){
            throw new IllegalArgumentException();
        }
        boolean flag = false;
        for(AdjacencyListHead adj : nodesList){
            if(adj.getNetNode().getId() == node.getId()){
                flag = true;
            }

        }
        if(!flag){
            throw new IllegalArgumentException();
        }
        nodesList.remove(node);
    }

    /**Method removeLink that removes the link between two nodes.
     *
     * @param node1 first node to be linked.
     * @param node2 second node to be linked.
     * @throws IllegalArgumentException exception that is thrown when nodes are null or already in nodesList.
     */
    public void removeLink(NetNode node1, NetNode node2)throws IllegalArgumentException
	{   
        if(node1 == null || node2 == null){
            throw new IllegalArgumentException();
        }
        boolean flag = false;
        boolean galf = false;
        for(AdjacencyListHead node : nodesList){
            if(node.getNetNode().getId() == node1.getId()){
                flag = true;
            }
            if(node.getNetNode().getId() == node2.getId()){
                galf = true;
            }
        }
        if(!flag && !galf){
            throw new IllegalArgumentException();
        }

        for(AdjacencyListHead adjNode : nodesList){
            if(adjNode.getNetNode().getId() == node2.getId()){
                LinkedList<Adjacent> a = adjNode.getAdjacencyList();
                a.remove(adjNode);
                adjNode.setAdjacencyList(a);
            }
            if(adjNode.getNetNode().equals(node2)){
                LinkedList<Adjacent> b = adjNode.getAdjacencyList();
                b.remove(adjNode);
                adjNode.setAdjacencyList(b);
            }

        }
    }

    /** getAdjacents that return the adjacent nodes to the node that is given.
     *
     * @param node one of the nodes that make up the plenty in nodesList.
     * @return a linked list of all the adjacent nodes to the node that is provided.
     * @throws IllegalArgumentException exception that is thrown when nodes are null or already in nodesList.
     */
    public LinkedList<Adjacent> getAdjacents(NetNode node)throws IllegalArgumentException{

        LinkedList<Adjacent> a = null;
        boolean flag = false;
        for(AdjacencyListHead adj : nodesList){
            if(adj.getNetNode().getId() == node.getId()){
                flag=true;
            }
        }if (!flag){throw new IllegalArgumentException();}

        for(AdjacencyListHead adjNode : nodesList){
            if(adjNode.getNetNode().getId() == node.getId()){//check everything name, id, getx, gety
                a = adjNode.getAdjacencyList();
            }
        }
        return a;

    }

    /** getNodeIndex method that when given a node reurns the index of the node.
     *
     * @param node one of the nodes that make up the plenty in nodesList.
     * @return nodesList.indexOf(node) returns the index of the node.
     * @throws IllegalArgumentException exception that is thrown when nodes are null or already in nodesList.
     */
    int getNodeIndex(NetNode node)throws IllegalArgumentException{

        for(AdjacencyListHead adj : nodesList){
            if(adj.getNetNode().getId() != node.getId()){
                throw new IllegalArgumentException();
            }
        }
       return nodesList.indexOf(node);
    }

    /** degree method that returns the number of adjacent nodes of a particular node.
     *
     * @param node one of the nodes that make up the plenty in nodesList.
     * @return getAdjacents(node).size() returns the number of adjacents to that node.
     */
    public int degree(NetNode node){ 
            return getAdjacents(node).size();
    }

    /** etGraphMaxDegree method that returns the maximum amount of adjacent nodes.
     *
      * @return maxDegree the max amount of adjacent nodes to a certain node.
     */
 public int getGraphMaxDegree()
	{
        int maxDegree = 0;
        for(AdjacencyListHead DegreeNode : nodesList){
            int Degree = degree(DegreeNode.getNetNode());

            if(Degree > maxDegree){
                maxDegree = Degree;
            }
        }
            return maxDegree;
	}

    /** nodeFromIndex returns the node given the index.
     *
     * @param index the integer valuye that corresponds the number node that is to be picked form nodesList.
     * @return nodesList.get(index).getNetNode() returns the node from the given index.
     */

public NetNode nodeFromIndex(int index){
        return nodesList.get(index).getNetNode();
    }

    /** PrintGraph method that prints a string representation of the graph with the nodes and the weight and adjacents.
     *
     * @return s.toString() returns the graph with the nodes and the weight and adjacents.
     */
    public String printGraph(){
        StringBuilder s = new StringBuilder();
        for(AdjacencyListHead node : nodesList){
            s.append(node.getNetNode().getName());
            s.append(":{");

            for(Adjacent adjacent : node.getAdjacencyList()){
                s.append("(");
                s.append(adjacent.getNeighbor().getName());
                s.append(",");
                s.append(adjacent.getWeight());
                s.append("), ");
            }
            s.delete(s.length()- 2, s.length());
            s.append("}\n");

        }
        return s.toString();
    }

}
