import java.util.Arrays;
public abstract class Game implements Comparable<Game>{
    private String puc;
    private String[] genres;
    abstract String getType();

    public Game(String puc, String[] genres){
        this.puc = puc;
        this.genres = genres;
    }

    public final String getPuc(){
        return this.puc;
    }
    public final String[] getGenres(){
        return this.genres;
    }
    public boolean equals(Object other){
        if(other == true){
            return true;
        }
        Game g = (Game) other;
        if (other instanceof Game) && (this.puc.equals(g.puc)){
            return true;
        }
        return false;

    }
    public String toString(){
        return "type: "  + this.getType() + ", puc: " + this.puc + ", genres: "  + Arrays.deepToString(genres);
    }
}






