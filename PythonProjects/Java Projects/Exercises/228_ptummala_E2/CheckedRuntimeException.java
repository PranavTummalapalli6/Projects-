public abstract class CheckedRuntimeException extends Exception{
  private Exception maskedRuntimeException;
  private CheckedRuntimeException(){
    
  }
  protected CheckedRuntimeException(String message, Exception maskedRuntimeException){
    super(message);
    if(maskedRuntimeException == null){
      throw new IllegalArgumentException();
    }
    this.maskedRuntimeException = maskedRuntimeException;
  }
  public Exception getRuntimeException(){
    // could this exception ever be thrown?
    // what if runtimeException is protected rather than private?
    if(maskedRuntimeException == null){
      throw new IllegalStateException();
    }
    return maskedRuntimeException;
  }
}
