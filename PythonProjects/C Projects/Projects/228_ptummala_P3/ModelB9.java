public class ModelB9 extends MovieRobot{

	public ModelB9(int serialNumber, boolean flies, boolean autonomous, boolean teleoperated, String catchphrase) {
		super(serialNumber, flies, autonomous, teleoperated, "Danger, Will Robinson!");
	}
	
    public boolean canFlail(){
        return true;
    }

	public String getCapabilities () {
        String s = new String("");
		if(canFlail() == true){
            return s += super.getCapabilities() + " canFlail";
        }
        else{
            return s += super.getCapabilities();
        }
        
	}


	public boolean canSpeak() {
		if(super.catchphrase!=null){
            return true;
        }
			
			return false;
	}

	
}