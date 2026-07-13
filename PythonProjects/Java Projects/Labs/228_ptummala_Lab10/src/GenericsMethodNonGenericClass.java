public class GenericsMethodNonGenericClass {
        public static <T> void genericsMethod(T [] data){
            for(T i: data) System.out.println(i + " ");
                System.out.println();
        }


    }

