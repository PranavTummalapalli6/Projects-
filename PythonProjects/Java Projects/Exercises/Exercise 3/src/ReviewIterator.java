import java.util.Iterator;

public class ReviewIterator implements Iterator<String> {

    private String[] str;
    private int temp = 0;

    public ReviewIterator(String comment){
        str = comment.split(" ");
    }

    @Override
    public boolean hasNext() {
        return temp < str.length;
    }

    @Override
    public String next() {
        return str[temp++];
    }

    @Override
    public void remove() {
        throw new UnsupportedOperationException();
    }


}
