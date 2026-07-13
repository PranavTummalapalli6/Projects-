//TODO: Complete java docs and code in missing spots.

import java.util.*;

/**
 * This is the class representing the complete MerkleTree.
 */
public class MerkleTree {
	public static MerkleTreeNode root;
	public int numberOfFiles;
    public static ArrayList<MerkleTreeNode> leaves;

	public String constructMerkleTree(String[] files) throws IllegalArgumentException{


		numberOfFiles = files.length;
		int i = 0;
		for(String file : files){
			leaves.add(new MerkleTreeNode(null,null,null, file));

		}


		root = notLeaf().get(0);


		if(files == null){

			throw new IllegalArgumentException();
		}
		return root.getStr();



		//Task 2: You are required to develop the code for the constructMerkleTree method.
		//Running time complexity of this method: O(n) where n is the number of files (size of the files array)
		//You can assume that the size of the files will be given as 2^n
		//throw IllegalArgumentException for invalid parameters

	}

	private ArrayList<MerkleTreeNode> notLeaf(){
		ArrayList<MerkleTreeNode> nonLeafNodes = new ArrayList<MerkleTreeNode>();
		ArrayList<MerkleTreeNode> parentNodes = new ArrayList<MerkleTreeNode>();

			for(int a = 0; a < numberOfFiles; a += 2) {
				MerkleTreeNode left = leaves.get(a);
				MerkleTreeNode right = leaves.get(a + 1);
				String hash = Hashing.cryptHash(left.getStr() + right.getStr());
				MerkleTreeNode parent = new MerkleTreeNode(null, left, right, hash);
				left.setParent(parent);
				right.setParent(parent);
				parentNodes.add(parent);
				MerkleTreeNode leftParent = parentNodes.get(a);
				MerkleTreeNode rightParent = parentNodes.get(a + 1);
				String Hashroot = Hashing.cryptHash(leftParent.getStr() + rightParent.getStr());
				MerkleTreeNode riot = new MerkleTreeNode(null, leftParent, rightParent, Hashroot);
				nonLeafNodes.add(riot);
			}
			nonLeafNodes.addAll(parentNodes);

		return nonLeafNodes;
		}


	
	public static boolean verifyIntegrity(String rootValue, int fileIndex, String file ) throws IllegalArgumentException{
		MerkleTreeNode node = leaves.get(fileIndex);

		MerkleTreeNode hash = node;
		String strs = hash.getStr();
		hash = hash.getParent();
		if(hash.getLeft() == node){
			strs = strs + hash.getRight().getStr();
		}
		else{
			strs = strs + hash.getLeft().getStr();
		}

		if(file == null){
			throw new IllegalArgumentException();
		}


		//Task 3: You are required to develop the code for the verifyIntegrity method
		//Running time complexity of this method: O(n)
		//throw IllegalArgumentException for invalid parameters
		return Objects.equals(rootValue, Hashing.cryptHash(strs));
	}

	public String swapFile(int fileIndex1, int fileIndex2){

		//Task 4: You are required to develop the code for the swapFile method.
		//Running time complexity of this method: O(n)
		//throw IllegalArgumentException for invalid parameters
		return "";
	}
        public static ArrayList<String> convertToDynamic(){
		//Task 5: You are required to develop the code for the convertToDynamic method.
		//Running time complexity of this method: O(n)
		return null;
        }
        public static boolean verifyIntegrityDynamic(String rootValue, int fileIndex, String file, ArrayList<String> dynamicMerkle) {
               //Task 6: You are required to develop the code for the verifyIntegrityDynamic method.
	       //Running time complexity of this method: O(n)
               return true;
           
	}
}
