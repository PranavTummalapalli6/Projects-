/**
 *  This class IntegrityCheckFailedException is a custom exception that is extended by Exception.
 *
 * @author Pranav Tummalapalli
 */


public class IntegrityCheckFailedException extends Exception{
	/** IntegrityCheckFailedException is an exception that states when the Authentification of the nodes digest and hash don't match.
	 *

	 */
	public IntegrityCheckFailedException(){
		System.out.println("Authentication Failed!");
	}

}