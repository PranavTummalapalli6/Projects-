public abstract class MovieRobot extends Robot{
    protected String catchphrase;


    public MovieRobot(int serialNumber, boolean flies, boolean autonomous, boolean teleoperated, String catchphrase){
        super(serialNumber, flies, autonomous, teleoperated);
        this.catchphrase = catchphrase;
    }
    public MovieRobot(int serialNumber, boolean flies, boolean autonomous, boolean teleoperated){
        super(serialNumber, flies, autonomous, teleoperated);
        this.catchphrase = null; 
    }
    public abstract boolean canSpeak();

    public String getCapabilities(){
        String s = new String("");

        if(canSpeak() == true){
            return s += super.getCapabilities() + " canSpeak";
        }
        else{
            return s += super.getCapabilities();
        }
       
        /*if(this.flies == true && this.autonomous == true && this.teleoperated == true && this.canClean == true && this.canSpeak == true){
            str += "canFly isAutonomous isTeleoperated canClean canSpeak";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == true && this.canClean == true && this.canSpeak == false){
            str += "canFly isAutonomous isTeleoperated canClean";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == true && this.canClean == false && this.canSpeak == true){
            str += "canFly isAutonomous isTeleoperated canSpeak";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == true && this.canClean == false && this.canSpeak == false){
            str += "canFly isAutonomous isTeleoperated";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == true && this.canClean == true && this.canSpeak == true){
            str += "canFly isTeleoperated canClean canSpeak";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == true && this.canClean == true && this.canSpeak == false){
            str += "canFly isTeleoperated canClean";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == true && this.canClean == false && this.canSpeak == true){
            str += "canFly isTeleoperated canSpeak";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == true && this.canClean == false && this.canSpeak == false){
            str += "canFly isTeleoperated";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == false && this.canClean == true && this.canSpeak == true){
            str += "canFly isAutonomous canClean canSpeak";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == false && this.canClean == true && this.canSpeak == false){
            str += "canFly isAutonomous canClean";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == false && this.canClean == false && this.canSpeak == true){
            str += "canFly isAutonomous canSpeak";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == false && this.canClean == false && this.canSpeak == false){
            str += "canFly isAutonomous";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == false && this.canClean == true && this.canSpeak == true){
            str += "canFly canClean canSpeak";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == false && this.canClean == true && this.canSpeak == false){
            str += "canFly canClean";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == false && this.canClean == false && this.canSpeak == true){
            str += "canFly canSpeak";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == false && this.canClean == false && this.canSpeak == false){
            str += "canFly";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == true && this.canClean == true && this.canSpeak == true){
            str += "isAutonomous isTeleoperated canClean canSpeak";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == true && this.canClean == true && this.canSpeak == false){
            str += "isAutonomous isTeleoperated canClean";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == true && this.canClean == false && this.canSpeak == true){
            str += "isAutonomous isTeleoperated canSpeak";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == true && this.canClean == false && this.canSpeak == false){
            str += "isAutonomous isTeleoperated";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == false && this.canClean == true && this.canSpeak == true){
            str += "isAutonomous canClean canSpeak";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == false && this.canClean == true && this.canSpeak == false){
            str += "isAutonomous canClean";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == false && this.canClean == false && this.canSpeak == true){
            str += "isAutonomous canSpeak";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == false && this.canClean == false && this.canSpeak == false){
            str += "isAutonomous";
        }
        if(this.flies == false && this.autonomous == false && this.teleoperated == true && this.canClean == true && this.canSpeak == true){
            str += "isTeleoperated canClean canSpeak";
        }
        if(this.flies == false && this.autonomous == false && this.teleoperated == true && this.canClean == true && this.canSpeak == false){
            str += "isTeleoperated canClean";
        }
        if(this.flies == false && this.autonomous == false && this.teleoperated == true && this.canClean == false && this.canSpeak == true){
            str += "isTeleoperated canSpeak";
        }
        if(this.flies == false && this.autonomous == false && this.teleoperated == true && this.canClean == false && this.canSpeak == false){
            str += "isTeleoperated";
        }*/
         
    }
    public String toString(){
        if(canSpeak() == false){
            return super.toString();
        }
        else{
            return super.toString() + " \"" + catchphrase + "\"";
        }
        
    }

}