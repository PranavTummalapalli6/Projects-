public class FirstPartyVideogame extends VideoGame{
    String getType() {
        return "First-Party";
    }
    public FirstPartyVideogame(String puc, String[] genres, String publisher, String director, Format[] formats, String[] developers, String title, int year){
        super(puc,genres, publisher, director, formats, developers, title, year);
    }
    // add compare to method
     /* if (this.getType().equals(g.getType())) {
        if(this.getYear()>(((VideoGame)g).getYear())){
            return 1;
        }
        else if(this.getYear()<(((VideoGame)g).getYear())){
            return -1;
        }*/
}
