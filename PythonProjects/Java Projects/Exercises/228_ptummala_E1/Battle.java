
public class Battle {
    
	public static void main(String[] args) {
		Hero h = new Hero("BOb", 50, 2, 3, 10);
		Monster m = new Monster("juice", 30, 30, 10, 10);
		System.out.println(fight(h, m));
	}

	public static String fight(Hero h, Monster m) {
		while (h.hasHPRemaining() && m.isDefeated() == false) {
			m.receiveAttack(h.attackRating);
			h.receiveAttack(m.attackRating);
			if (h.hasHPRemaining() == false) {
				h.useHealingPotion();
			}
		}

		if (h.hasHPRemaining() == false) {
			return "The " + m.type + " has defeated " + h.name + ". " + "Game over.";
		} else {
			h.receiveXP(m.xpValue);
			h.healingPotions = h.healingPotions + (m.goldValue / 3);
			return h.name + " has defeated the " + m.type + " earning " + m.goldValue + " gold " + h.currentXP + " XP leveling up " + h.currentLevel + " times";
		}
	}
}