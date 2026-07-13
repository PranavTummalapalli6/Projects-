public class Car{
    
    private String model;
    private String color; 
    private String make; 
    private float price;

   
    public Car(String model, String make, String color){
        this.model = model;
        this.make = make;
        this.color = color;
    }
    
    public Car(String model, String make, String color, float price){
        this(model, make, color);
        this.price = price;
    }

    public float getPrice(){
        return this.price;
    }
    public String getModel(){
        return this.model;
    }
    public void setPrice(float price){
        this.price = price;
    }
    public void printCarDetails(){
        System.out.println("Car Model: " + model + ", " + "Color: " + color + ", " + "Make: " + make + ", " + "Price: $" + price );
    }
    

}