public class ReleasedGame <K,V extends Comparable<V>> implements Comparable< ReleasedGame <K,V>> {
    private K key;
    private V value;

    public K getKey() {
        return key;
    }

    public V getValue() {
        return value;
    }

    public ReleasedGame(K key, V value){
        this.key = key;
        this.value = value;
    }
    public boolean equals(Object other){
        boolean flag = true;
        if (other.equals(true)) {
             flag = true;
        }
        else{
            flag = false;
        }
        ReleasedGame g = (ReleasedGame) other;

        if (!(other instanceof ReleasedGame)) {
             flag = false;
        }
        else{
            flag = false;
        }
        if(this.getValue().equals(((ReleasedGame<K, V>) other).getValue())) {
             flag = true;
        }
        else{
            flag = false;
        }

        return flag;
    }
    public int compareTo(ReleasedGame <K, V> g){
        return this.getValue().compareTo(g.getValue());
    }
}
