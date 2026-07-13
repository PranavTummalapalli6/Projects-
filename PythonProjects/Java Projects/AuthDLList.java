/**
 *  This class has code that provides the basics for the BlockChain technology to work by utilizing
 *  java linked list nodes to depict each file that is in the extensive blockchain.
 *
 *
 * @author Pranav Tummalapalli
 */
public class AuthDLList{

	/**
	 * stores the start digest hash code into a String called Start Digest.
	 */
	public static final String startDigest = "123456789";
	/**
	 * Instantiates the Node head.
	 */
	public Node head;
	/**
	 * instantiates the tail of the node.
	 */
	public Node tail;
	/**
	 * private temp node.
	 */
	private Node tempNode;

	/**Boolean method Verify Integrity that checks if the hash code is the same as the digest to prevent no tampering.
	 *
	 * @param currentList  the doubly linked list that all the nodes will be added onto.
	 * @param check  the hash code of the last value in the linked list the tail.
	 * @return true returns boolean value true.
	 * @throws IntegrityCheckFailedException when the digest of the node does not match the hash code.
	 */
	public static boolean verifyIntegrity(AuthDLList currentList, String check) throws IntegrityCheckFailedException {
		
		Node currNode = currentList.head;
		boolean initial = true;
		while(currNode != null){
			if(initial){
				String hash = Hashing.cryptHash(AuthDLList.startDigest + "&" + currNode.file);
				if(!currNode.digest.equals(hash)) {
					throw new IntegrityCheckFailedException();
				}
				initial = false;
				currNode = currNode.next;
			}
			else if(currNode == currentList.tail){

				if(!currNode.digest.equals(check)){
					throw new IntegrityCheckFailedException();
				}

                                
				currNode = currNode.next;
			}
			else{
				String hash = Hashing.cryptHash(currNode.previous.digest + "&" + currNode.file);
				if(!currNode.digest.equals(hash)){
					throw new IntegrityCheckFailedException();
				}
				currNode = currNode.next;
			}
		}
		return true;
	}

	/**InsertFileNode method of type string that returns the digest of the new node that is added to the end of the linked list.
	 *
	 * @param data  the data or the file of the node.
	 * @param check  the hash code of the last node in the linked list the tail.
	 * @return newNode.digest returns the digest of the newNode that is added.
	 * @throws IntegrityCheckFailedException is thrown if Verify integrity method is not true.
	 */
	public String insertFileNode(String data, String check) throws IntegrityCheckFailedException {
		Node newNode = new Node();
		if(verifyIntegrity(this, check)){

			newNode.file = data;

			if(this.head == null){
				newNode.digest = Hashing.cryptHash(AuthDLList.startDigest + "&" + newNode.file);
				this.head = newNode;
				this.tail = newNode;
			}
			else{
				Node temp = this.tail;
				this.tail.next = newNode;
				newNode.digest = Hashing.cryptHash(check + "&" + data);
				this.tail = newNode;
				this.tail.previous = temp;
			}
		}
		return newNode.digest;
	}
	/**Delete first file method deletes the data and the first node of the linked list.
	 *
	 * @param check  the hash code of the last node in the linked list of the tail.
	 * @return this.tail.digest returns the digest of the very last node of the linked list the tail.
	 * @throws IntegrityCheckFailedException is thrown if Verify integrity method is not true.
	 * @throws EmptyDLListException is thrown is the Linked list is empty.
	 */
	public String deleteFirstFile(String check) throws IntegrityCheckFailedException, EmptyDLListException {
		Node tempNode = new Node();
		if(verifyIntegrity(this, check)){


			if(this.head == null){
				throw new EmptyDLListException();
			}

			else{
				this.head = this.head.next;
				this.head.previous.next = null;
				this.head.previous = null;

				this.head.digest = Hashing.cryptHash(AuthDLList.startDigest + "&" + this.head.file);



				tempNode = this.head.next;
				while(tempNode != null){
					tempNode.digest = Hashing.cryptHash(tempNode.previous.digest + "&" + tempNode.file);
					tempNode = tempNode.next;
				}
			}


		}
		return this.tail.digest;

	}

	/**Delete last file method deletes the data and the last node of the linked list.
	 *
	 * @param check  the hash code of the last node in the linked list of the tail.
	 * @return this.tail.digest returns the digest of the very last node of the linked list the tail.
	 * @throws IntegrityCheckFailedException is thrown if Verify integrity method is not true.
	 * @throws EmptyDLListException is thrown is the Linked list is empty.
	 */
	public String deleteLastFile(String check) throws IntegrityCheckFailedException, EmptyDLListException {
		if(verifyIntegrity(this, check)){

			if(this.head == null){
				throw new EmptyDLListException();
			}
			else if(this.head.next == null){
				this.tail = null;
				this.head = null;
				return AuthDLList.startDigest;
			}
			else{
				this.tail = this.tail.previous;
				this.tail.next.previous = this.tail;
				this.tail.next = null;


			}

		}

		return this.tail.digest;
	}

	/** retriveNode file method is the method that retrieves the node that has the certain file in it.
	 *
	 * @param current  The linked list.
	 * @param check  the hash code of the last node in the linked list of the tail.
	 * @param file  the given file that the user is searching for in each node's data.
	 * @return tempNode returns the tempNode that is found to have the certain file that is given in it.
	 * @throws IntegrityCheckFailedException is thrown if Verify integrity method is not true.
	 * @throws FileNotFoundException is thrown when the file is not found in all the nodes.
	 */
	public static Node retrieveNodeFile(AuthDLList current, String check, String file) throws IntegrityCheckFailedException, FileNotFoundException{
		Node tempNode = current.head;
		if(verifyIntegrity(current, check)) {
			while(tempNode != null){

				if(tempNode.file.equals(file)){
					return tempNode;
				}

				tempNode = tempNode.next;

				}
			throw new FileNotFoundException();




		}

		return tempNode;
	}

}
