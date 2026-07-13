public class Vacuum extends Robot{
    
    public Vacuum(int serialNumber){
        super(serialNumber, false, true, false);

    }
    public boolean canClean(){
        return true;
    }
    public boolean canFly(){
        return false;
    }
    public boolean isAutonomous(){
        return true;
    }
    public boolean isTeleoperated(){
        return false;
    }
    
    public String getCapabilities(){
        String s = new String("");
        
        if(canClean() == true){
            return s += super.getCapabilities() + " canClean";
        }
        else{
            return s += super.getCapabilities();
        }
        
       /* 
        if(this.flies == true && this.autonomous == true && this.teleoperated == true && this.canClean == true){//cant call robot class like this
            str += "canFly isAutonomous isTeleoperated canClean";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == true && this.canClean == false){
            str += "canFly isAutonomous isTeleoperated";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == true && this.canClean == true){
            str += "canFly isTeleoperated canClean";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == true && this.canClean == false){
            str += "canFly isTeleoperated";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == false && this.canClean == true){
            str += "canFly isAutonomous canClean";
        }
        if(this.flies == true && this.autonomous == true && this.teleoperated == false && this.canClean == false){
            str += "canFly isAutonomous";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == false && this.canClean == true){
            str += "canFly canClean";
        }
        if(this.flies == true && this.autonomous == false && this.teleoperated == false && this.canClean == false){
            str += "canFly";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == true && this.canClean == true){
            str += "isAutonomous isTeleoperated canClean";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == true && this.canClean == false){
            str += "isAutonomous isTeleoperated";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == false && this.canClean == true){
            str += "isAutonomous canClean";
        }
        if(this.flies == false && this.autonomous == true && this.teleoperated == false && this.canClean == false){
            str += "isAutonomous";
        }
        if(this.flies == false && this.autonomous == false && this.teleoperated == true && this.canClean == true){
            str += "isTeleoperated canClean";
        }
        if(this.flies == false && this.autonomous == false && this.teleoperated == true && this.canClean == false){
            str += "isTeleoperated";
        }*/
         
    }
}
