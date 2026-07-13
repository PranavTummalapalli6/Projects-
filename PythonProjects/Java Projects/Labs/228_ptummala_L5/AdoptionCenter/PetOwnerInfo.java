package AdoptionCenter;/*
Package name is Adoption Center
*/

public class PetOwnerInfo{//public class
    private String name;// instantiating of all the private variables
    private String email;
    private int age;

    public PetOwnerInfo( String name, String email, int age){// constructor to set the values from a parmeterixed constructor that sets all the attributes
        this.name = name;
        this.email = email;
        this.age = age;

    }
    public getName(String name){//getter
        return name;
    }
    public setEmail(String email){//setter
        this.email = email;
    }
    public String display(){//display method that prints out the string
        return( name + " is " + age + " years old. " + "Thier email is " + email);
    }
}