import AdoptionCenter.name.*; 
public class AdoptionDriver{
    public static void main(String[] args){

        if(args.length != 7){
            System.out.println("Invalid number of arguments. ");

        }

        else{
        
        String petType = args[0];
        String petName = args[1];
        double petWeight = Double.parseDouble(args[2]);
        int petAge = Integer.parseInt(args[3]);

        PetInfo MyPet = new PetInfo(petType, petName, petWeight, petAge);
        System.out.println(MyPet.display());

        String ownerName = args[4];
        Stirng ownerEmail = args[5];
        int ownerAge = Integer.parseInt(args[6]);

        PetOwnerInfo myOwner = new PetOwnerInfo(ownerName, ownerEmail, ownerAge);
        System.out.println(myOwner.display());


    }
}
}