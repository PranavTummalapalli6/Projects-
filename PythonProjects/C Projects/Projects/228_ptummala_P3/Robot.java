public class Robot {
    private int serialNumber;
    private boolean flies;
    private boolean autonomous;
    private boolean teleoperated;

    public Robot(int serialNumber, boolean flies, boolean autonomous, boolean teleoperated){
        this.serialNumber = serialNumber;
        this.flies = flies;
        this.autonomous = autonomous;
        this.teleoperated = teleoperated;
    }

    public void setCapabilities(boolean flies, boolean autonomous, boolean teleoperated){
        this.flies = flies;
        this.autonomous = autonomous;
        this.teleoperated = teleoperated;
    }

    public int getSerialNumber(){
        return this.serialNumber;
    }
    public boolean canFly(){
        return this.flies;
    }
    public boolean isAutonomous(){
        return this.autonomous;
    }
    public boolean isTeleoperated(){
        return this.teleoperated;
    }
    public String getCapabilities(){
        String s = new String("");
       
        if(this.flies == true && this.autonomous == true && this.teleoperated == true){
            s += "canFly isAutonomous isTeleoperated";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == true){
            s += "canFly isTeleoperated";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == false){
            s += "canFly isAutonomous";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == false){
            s += "canFly";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == true){
            s += "isAutonomous isTeleoperated";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == false){
            s += "isAutonomous";
        }
        if(this.flies == false && this.autonomous == false && this.teleoperated == true){
            s += "isTeleoperated";
        }
        return s;
         
    }
    public String toString(){
        return "ID: "+ this.serialNumber + ", Capabilities: " + getCapabilities();
    }
    
}
