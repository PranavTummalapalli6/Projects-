public class GameCatalogException extends Exception{
    private final String puc;

    GameCatalogException(String puc, Game game){
        super("the game’s PUC is already in the catalog.");
        this.puc = puc;
    }
}

