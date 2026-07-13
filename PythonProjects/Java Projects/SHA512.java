//TODO: Complete java docs and code in missing spots.
import java.security.*;
import java.nio.charset.*;
/**
 *  This code is already made for you, it is extended by Hashing to generate the SHA-512 hash of a String. No explicit call to any method here is required.
 *
 * @author Pranav Tummalapalli
 */


public class SHA512 {
    /**String method hashSha512 that genederates the sha-512 hash from a string.
     *
     * @param message  the message used to hash.
     * @return sha512ValueHexa returns the Hexadecimal value of the digest.
     * @throws NoSuchAlgorithmException thrown when there is no such alogithm.
     */
    protected static String hashSHA512(String message) {
        String sha512ValueHexa = "";
        try {
            MessageDigest digest512 = MessageDigest.getInstance("SHA-512");
            sha512ValueHexa = byteToHex(digest512.digest(message.getBytes(StandardCharsets.UTF_8)));
        }
        catch(NoSuchAlgorithmException exp) {
            exp.getMessage();
        }
        return sha512ValueHexa;
    }
    /**String method byte to hex that transforms the byte values into hexadecimal values.
     *
     * @param digest  byte array.
     * @return output returns the Hexadecimal output of the byte into a hexadecimal value.
     */
    public static String byteToHex(byte[] digest) {
        StringBuilder vector = new StringBuilder();
        for (byte c : digest) {
            vector.append(String.format("%02X", c));
        }
        String output = vector.toString();
        return output;
    }
}
