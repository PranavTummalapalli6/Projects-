public class Drone extends Robot{
    
    public Drone(int serialNumber){
        super(serialNumber, true, false, true);

    }
    public boolean canFly(){
        return true;
    }
    public boolean isAutonomous(){
        return false;
    }
    public boolean isTeleoperated(){
        return true;
    }

}