import java.util.List;
public class GameSearcher implements Searchable{

    List<String> searchTerms;

    public GameSearcher(List<String> searchTerms){
        this.searchTerms = searchTerms;
    }

    @Override
    public boolean matches(ReleasedGame<String, Game> ReleasedGame) {
        for (int i = 0; i < searchTerms.size(); i++) {
            String searchTerm = searchTerms.get(i);
            if (ReleasedGame.getValue().toString().contains(searchTerm)) {
                return true;
            }
        }
        return false;
    }
}
