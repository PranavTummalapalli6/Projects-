import java.util.Iterator;

public class Review implements Iterable<String>{

    private String username;
    private int rating;
    private String comment;

        public Review(String username, int rating, String comment){
            this.username = username;
            this.rating  = rating;
            this.comment = comment;
        }

        public String getUsername(){
            return username;
        }

        public int getRating(){
            return rating;
        }

        public int getCommentSize(){
            String[] str = comment.split(" ");
            return str.length;
        }

        public String getCommentWord(int N){
            String[] str = comment.split(" ");
            return str[N];
        }

    @Override
    public Iterator<String> iterator() {
        return new ReviewIterator(comment);
    }

    public Iterator<String> iterator(boolean skipSuspiciousWords){
        ReviewIterator onj =  new ReviewIterator(comment);
            if(skipSuspiciousWords == false){
                onj =  new ReviewIterator(comment);
            }
            else{
                for(int i = 0; i < getCommentSize(); i++) {
                    if(getCommentWord(i).equals("veritas") || getCommentWord(i).equals("moribus")|| getCommentWord(i).equals("inmaturitas")|| getCommentWord(i).equals("malignus")){
                        onj =  new ReviewIterator(getCommentWord(i));
                    }
                }

            }
        return onj;
    }
}