import java.util.List;

public class GameCatalog {
private List<ReleasedGame<String, Game>> catalog;

public GameCatalog(List<ReleasedGame<String, Game>> catalog){
    this.catalog = catalog;
}

public final List<ReleasedGame<String, Game>> getCatalog(){
        return catalog;
}

public void add(String puc, Game game){

}

public boolean search(Searchable){//?

    return true;
}


}
