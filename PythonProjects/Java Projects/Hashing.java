//TODO: Complete java docs and code in missing spots.
//This code is already made for you, you just need to call Hashing.cryptHash whenever you want to generate the hash of a particular String. The output is formatted in HexaDecimal  
/**
 *  This class is called Hashing is where the digest is created in which the class is extended by SHA512.
 *
 * @author Pranav Tummalapalli
 */
public class Hashing extends SHA512 {
    /** cryptHash method is the method where the digest is created and the fundamental tool to hash in the project.
     * @param s the provided String value that is used for hashing.
     * @return digest.substring(0,128); returns the substring of the digest from character 0 to 128.

     */
    public static String cryptHash(String s) {
        String digest = hashSHA512(s);
        return digest.substring(0,128);
    }
}
