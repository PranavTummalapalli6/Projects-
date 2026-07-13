import java.util.Arrays;

public abstract class VideoGame extends Game {
    String publisher, director;
    Format[] formats;
    String[] developers;
    String title;
    int year;

    abstract String getType();

    VideoGame(String puc, String[] genres, String publisher, String director, Format[] formats, String[] developers, String title, int year) {
        super(puc, genres);
        this.publisher = publisher;
        this.director = director;
        this.formats = formats;
        this.developers = developers;
        this.title = title;
        this.year = year;
    }

    public final String getPublisher() {
        return this.publisher;
    }

    public final String getDirector() {
        return this.director;
    }

    public final Format[] getFormats() {
        return this.formats;
    }

    public final String[] getDevelopers() {
        return this.developers;
    }

    public final String getTitle() {
        return this.title;
    }

    public final int getYear() {
        return this.year;
    }


    @Override
    public String toString() {

        return "publisher: " + this.publisher + ", director: " + this.director + ", formats: " + Arrays.deepToString(this.formats) + ", developers: " + Arrays.deepToString(this.developers) + ", title: " + this.title + ", year: " + String.valueOf(this.year) + ", " + super.toString();

    }

    public int compareTo(Game g) {

            return 0;
        }
}


