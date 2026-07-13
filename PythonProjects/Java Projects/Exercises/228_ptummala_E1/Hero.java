public class Hero{
    public String name;
    public int hitPointsRemaining;
    public int hitPointsMax;
    public int attackRating;
    public int defenseRating;
    public int currentXP;
    public int currentLevel;
    public int healingPotions;

    public Hero(String name, int hpMax, int ar, int dr, int potions) {
        this.name = name;
        this.hitPointsRemaining = hpMax;
        this.attackRating = ar;
        this.defenseRating = dr;
        this.healingPotions = potions;
        this.currentXP = 0;
        this.currentLevel = 1;

    }
    public boolean hasHPRemaining(){
        if(hitPointsRemaining > 0){
            return true;
        }
        return false;
    }

    public void receiveAttack(int incAttack){
        if(incAttack > defenseRating){
            hitPointsRemaining = hitPointsRemaining - (incAttack - defenseRating);
        }

    }
    public void receiveXP(int xpReceived){
        if((xpReceived + 1) / 10 != 0){
            currentLevel += xpReceived / 10;
        }
        currentXP += xpReceived;
        hitPointsMax = currentLevel * 5;
        hitPointsRemaining = hitPointsMax;
    }
    public void useHealingPotion(){
        if(healingPotions > 0){
            hitPointsRemaining = hitPointsMax;
            healingPotions -= 1;
        }
    }

}