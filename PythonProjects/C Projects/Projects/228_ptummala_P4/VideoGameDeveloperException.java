public class VideoGameDeveloperException extends Exception{
    private final String developer;

    VideoGameDeveloperException(String developer, Game videogame){
            super("a developer is preventing adding the videogame to the catalog.");
            this.developer = developer;
        }
    }

