import java.util.ArrayList;
import java.util.List;
class Main {
    public static void main(String[] args) {

        GenericsMethodNonGenericClass generic = new GenericsMethodNonGenericClass();

        String[] string = {"Java, Programming"};
        Integer[] integer = {2,1,4,3,6,5};
        Double[] double1 = {3.23, 5.53, 7.0};

        generic.genericsMethod(string);
        generic.genericsMethod(integer);
        generic.genericsMethod(double1);

        Pair<String, Integer> pair1 = new Pair<>("Key", 0);





    }
}
