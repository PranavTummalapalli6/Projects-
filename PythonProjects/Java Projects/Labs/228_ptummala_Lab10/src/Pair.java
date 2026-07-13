public class Pair<K,V> {
    private K k;
    private V v;
    public Pair(K k, V v){
        this.k = k;
        this.v = v;
    }
    public String toString(){
        return "Key = " + k.getClass().getName() + " and " + "Value = " + v.getClass().getName();
    }

}
