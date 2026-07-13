public class VideogameException extends Exception{
    private final String fieldName;

    VideogameException(String fieldName){
        super("an argument has null or illegal values.");
        this.fieldName = fieldName;

    }
}
