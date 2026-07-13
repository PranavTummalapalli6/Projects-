public class ShapeException extends CheckedRuntimeException{
    ShapeException(String message, Exception e){
        super(message, e);
    }
}
//15