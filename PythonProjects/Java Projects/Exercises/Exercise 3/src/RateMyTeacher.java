import java.io.File;

public class RateMyTeacher {
    public static void main(String[] args) {
        File f = new File(args[0]);
        ReviewList a = new ReviewList(f);
        for(Review R : a){
            for(String s : R){
                System.out.println(s);
            }

        }

    }
}

