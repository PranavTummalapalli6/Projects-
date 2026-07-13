package AdoptionCenter;/*
Package name is Adoption Center
*/

public class PetInfo{.//public class
    private String name;// instantiating of all the private variables
    private int age;
    private double weight;
    private String type;

    public PetInfo( String name, int age, double weight, String type){// constructor to set the values from a parmeterixed constructor that sets all the attributes
        this.name = name;
        this.age = age;
        this.weight = weight;
        this.type = type;
    }
    public setAge(int age){//setter 
        this.age = age;
    }
    public getName(String name){//getter
        return name;
    }
    public String display(){//display method that prints out the string
        return(name + "is a " + type + " who is " + age + " years old and weighs " + weight + "lbs.");
    }

}