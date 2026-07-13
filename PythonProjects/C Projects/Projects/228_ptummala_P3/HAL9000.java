public class HAL9000 extends MovieRobot {

	public HAL9000(int serialNumber, boolean flies, boolean autonomous, boolean teleoperated, String catchphrase) {
		super(serialNumber, true, autonomous, teleoperated, "I can't let you do that Dave.");
	}

	@Override
	public boolean canSpeak() {
		if(super.catchphrase !=null){
            return true;
        }
		
		return false;
	}

	
}