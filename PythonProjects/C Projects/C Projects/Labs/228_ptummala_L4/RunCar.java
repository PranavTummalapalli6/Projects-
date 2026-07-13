public class RunCar
{
    public static void main(String[] args){
        Car toyota = new Car("Camry", "toyota", "red");
        toyota.printCarDetails();

        toyota.setPrice(50000);
        toyota.printCarDetails();

        Car honda = new Car("Accord", "Honda", "Gold", 200000);
        System.out.println("The price of " + honda.getModel() + " is $" + honda.getPrice());

    }
}