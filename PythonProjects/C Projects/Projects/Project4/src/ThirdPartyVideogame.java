public class ThirdPartyVideogame extends VideoGame{
    String getType() {
        return "Third-Party";
    }
    public ThirdPartyVideogame(String puc, String[] genres, String publisher, String director, Format[] formats, String[] developers, String title, int year){
        super(puc,genres, publisher, director, formats, developers, title, year);
    }
}
