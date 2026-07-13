public class WALL_E extends MovieRobot{

	public WALL_E(int serialNumber, boolean flies, boolean autonomous, boolean teleoperated, String catchphrase) {
		super(serialNumber, flies, autonomous, teleoperated);
	}


	public boolean canSpeak() {
		return false;
	}

    public boolean canClean(){
        return true;
    }


	public String getCapabilities () {
        String s = new String("");
        if(canClean() == true){
            return s += super.getCapabilities() + " canClean";
        }
        else{
            return s += super.getCapabilities();
        }
		
	}
	
	
}