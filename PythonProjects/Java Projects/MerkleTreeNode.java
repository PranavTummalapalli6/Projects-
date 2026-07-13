//TODO: Complete java docs and code in missing spots.
/**
 * This class is used to represent nodes in the Merkle Tree.
 * Task 1: You are required to develop the constructor and the set and get methods of all the instance variables of this class.
 */
public class MerkleTreeNode{
    private MerkleTreeNode parent;
    private MerkleTreeNode left;
    private MerkleTreeNode right;
    private String str;

	/**
	 * Develop a default MerkleTreeNode constructor that initializes the instance variables to null.
	 */
	public MerkleTreeNode(){
		this.parent = null;
		this.left = null;
		this.right = null;
		this.str = null;
	}
	
	/**
	 * Develop a MerkleTreeNode Constructor that initiates the object with the parent, left, and right MerkleTreeNode objects.
	 */
	public MerkleTreeNode(MerkleTreeNode parent,MerkleTreeNode left,MerkleTreeNode right,String str){
		this.parent = parent;
		this.left = left;
		this.right = right;
		this.str = str;
	}

	/**
	 * Develop the set and get methods for the instance variables parent, left, right and str.
	 * @return 
	 */
	public MerkleTreeNode getParent(){
		return null;
	}

	public MerkleTreeNode getLeft(){
		return null;
	}
		
	public MerkleTreeNode getRight(){
		return null;
	}

	public String getStr(){
		return "";
	}
	
	public void setParent(MerkleTreeNode parent) throws IllegalArgumentException{
		if(parent == null){
			throw new IllegalArgumentException();
		}
		this.parent = parent;
		//throw IllegalArgumentException for invalid parameters
	}
	public void setLeft(MerkleTreeNode left) throws IllegalArgumentException{
		if(left == null){
			throw new IllegalArgumentException();
		}
		else {
			this.left = left;
		}
		//throw IllegalArgumentException for invalid parameters
	}
	public void setRight(MerkleTreeNode right) throws IllegalArgumentException{
		//throw IllegalArgumentException for invalid parameters
		if(right == null){
			throw new IllegalArgumentException();
		}
		else {
			this.right = right;
		}
	}
	public void setStr(String str) throws IllegalArgumentException{
		//throw IllegalArgumentException for invalid parameters
		if(str == null){//need to change this to something
			throw new IllegalArgumentException();
		}
		else {
			this.str = str;
		}
	}        
        
}