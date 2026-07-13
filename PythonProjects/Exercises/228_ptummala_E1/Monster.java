public class Monster{
    
    public String type;
    public int hitPoints;
    public int attackRating;
    public int xpValue;
    public int goldValue;


    public Monster(String type, int hp, int attackR, int xp, int gold) {
        this.type = type;
        this.hitPoints = hp;
        this.attackRating = attackR;
        this.xpValue = xp;
        this.goldValue = gold;
    }

    public Monster(){
        this.type = "Goblin";
        this.hitPoints = 10;
        this.attackRating = 1;
        this.xpValue = 1;
        this.goldValue = 1;
        
    }
    public boolean isDefeated(){
        if(hitPoints <= 0){
            return true;
        }
        return false;
    }
    public void receiveAttack(int incAttack){
        hitPoints -= incAttack;
    }


}