import java.io.File;
import java.io.FileNotFoundException;
import java.util.*;


public class ReviewList implements Iterable<Review>  {

    private ArrayList <Review> reviewlist =  new ArrayList <Review>();
    private int temp = 0;

    public ReviewList(File f) {
        try {
            Scanner sc = new Scanner(f);

            while(sc.hasNext()){
                String username = sc.nextLine();
                int rating = Integer.parseInt(sc.nextLine());
                String comment = sc.nextLine();
                reviewlist.add(new Review(username, rating, comment));
            }
            //reviews = reviewlist.toArray(new Review[reviewlist.size()]);


        }
        catch (FileNotFoundException e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public Iterator<Review> iterator() {
        return new Iterator<Review>(){

            @Override
            public boolean hasNext() {
                return temp < reviewlist.size();
            }

            @Override
            public Review next() {
                return reviewlist.get(temp++);
            }

            @Override
            public void remove() {
                throw new UnsupportedOperationException();
            }
        };
    }
    public Iterator<Review> iterator(boolean skipSuspiciousReview) {
        ArrayList<Review> revisedList;
        if (skipSuspiciousReview == false) {
            return new Iterator<Review>() {
                @Override
                public boolean hasNext() {
                    return temp < reviewlist.size();
                }

                @Override
                public Review next() {
                    return reviewlist.get(temp++);
                }

                @Override
                public void remove() {
                    throw new UnsupportedOperationException();
                }
            };

        }//take teh array list alrdy have remove all the sussy reviews make an iterator for the edited array list
        // take deep copy of reviewList and remove
        else {
            int count = 0;
            revisedList = new ArrayList<Review>();
            ArrayList<Review> cloneList = new ArrayList<Review>();
            cloneList = (ArrayList<Review>) reviewlist.clone();
            ArrayList<String> sussyWords = new ArrayList<String>();
            sussyWords.add("morbius");
            sussyWords.add("veritas");
            sussyWords.add("inmaturitas");
            sussyWords.add("malignus");
            for (Review R : cloneList) {
                //count++;
                //ReviewIterator onj =  new ReviewIterator(this.toString());
                //if(R.getCommentWord(count).equals("veritas") || R.getCommentWord(count).equals("moribus")|| R.getCommentWord(count).equals("inmaturitas")|| R.getCommentWord(count).equals("malignus")){
                //onj =  new ReviewIterator(R.getCommentWord(count));
                Iterator<String> a = R.iterator(skipSuspiciousReview);
                while (a.hasNext()) {
                    if (!sussyWords.contains(a.next())) {
                        count++;
                    }
                }

                if (R.getRating() == 5 && count <= 10) {
                    continue;

                } else {
                    revisedList.add(R);
                }
                return (Iterator<Review>) revisedList;

            }


        }

        return (Iterator<Review>) revisedList;

    }

}
