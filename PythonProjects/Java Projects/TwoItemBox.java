/**
 *  Code that creates a two item box with private items item1 and item 2.
 * @author Pranav Tummalapalli
 *
 * @param <T> Generic type T accessible to the whole class
 * @param <P> Generic type P accessible to the whole class
 */
public class TwoItemBox<T,P> {
    /**
     *  private data field of generic type T.
     *
     * @param item1 the first boxed item
     */

    private T item1;


    /**
     *  private data field of generic type P.
     *
     * @param item2 the second boxed item
     */
    private P item2;

    /**
     *  Constructor initializing TwoItemBox.
     *
     * @param item1 the first boxed item
     * @param item2 the second boxed item
     */
    public TwoItemBox(T item1, P item2){
        this.item1 = item1;
        this.item2 = item2;
    }
    /**
     *  A getter for the Two item box.
     *
     * @return item1 as an access modifier
     *
     */

    public T getItem1(){
        return item1;
    }
    /**
     *  A getter for the Two item box.
     *
     * @return item2 as an access modifier
     *
     */

    public P getItem2(){
        return item2;
    }
}
