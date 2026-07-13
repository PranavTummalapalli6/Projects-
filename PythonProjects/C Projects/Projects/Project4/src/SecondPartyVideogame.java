public class SecondPartyVideogame extends VideoGame{
    String getType() {
        return "Second-Party";
    }
    public SecondPartyVideogame(String puc, String[] genres, String publisher, String director, Format[] formats, String[] developers, String title, int year){
        super(puc,genres, publisher, director, formats, developers, title, year);
    }
}
