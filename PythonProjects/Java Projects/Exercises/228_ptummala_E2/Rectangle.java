public class Rectangle extends Shape implements AreaCalculator{
	private int otherSide;

	public Rectangle (MeasuringUnit unit, Integer side, Integer otherSide) throws CheckedRuntimeException {
		super(unit, side);
		this.otherSide = otherSide;
		/*if(unit == null){
			throw new ShapeException("", new NullPointerException()); //should pertain to all of shape heirarchy
		}
		if(side < 0){
			throw new ShapeException("", new IllegalArgumentException());
		}*/
		if(otherSide < 0){
			throw new ShapeException("Value is below zero", new IllegalArgumentException());
		}

	}

	public int getArea() throws CheckedRuntimeException{
		int result = 0;

		result += super.getSide()*otherSide;//catch shape and area exception

		if(result > Integer.MAX_VALUE){
			throw new AreaCalculatorException("The value is beyond the data type's max value", new ArithmeticException());
		}

		if(result < 0){
			throw new ShapeException("Value is below zero", new IllegalArgumentException());
		}
		return result;
	}

	// the default measuring unit is determined by unit
	public long convertArea(long area, MeasuringUnit ms) throws CheckedRuntimeException{//convert meters to feet
		if(ms == null){
			throw new MeasuringUnitException("The measuring unit is null",new NullPointerException());
		}
		if(ms == MeasuringUnit.METERS) {
			area = (long) (area * 3.281);
		}
		if(area > Long.MAX_VALUE){
			throw new AreaCalculatorException("The value is beyond the data type's max value", new ArithmeticException());
		}
		if(area < 0){
			throw new ShapeException("Value is below zero", new IllegalArgumentException());
		}

		return area;//AreaCalculatorException

	}

	// the default measuring unit is determined by unit, use super.getSide() and otherSide for sum of the areas, only one area in this case
	public long getTotalArea() throws CheckedRuntimeException{
		long result = 0;
		result += (long) super.getSide() * otherSide;

		/*if(result < 0){
			throw new ShapeException("", new IllegalArgumentException());
		}*/

		if(result > Long.MAX_VALUE){
			throw new AreaCalculatorException("The value is beyond the data type's max value", new ArithmeticException());
		}
		return result;

	}

	// the default measuring unit is determined by unit, use super.getSide() and otherSide for sum of the areas, only one area in this case
	public long getTotalArea (MeasuringUnit ms) throws CheckedRuntimeException{//throw exception for negative
		if(ms == null){
			throw new MeasuringUnitException("The Measuring unit is null", new NullPointerException());
		}
		long result = 0;
		result += (long) super.getSide() * otherSide;

		if(ms != MeasuringUnit.METERS){//convertArea
			return (long) ((result) * 3.281);
		}
		if(result > Long.MAX_VALUE){
			throw new AreaCalculatorException("The value is beyond the data type's max value", new ArithmeticException());
		}
		/*if(result < 0){
			throw new ShapeException("", new IllegalArgumentException());
		}*/

		return result;
	}

	public String toString(){
		return "Rectangle: {otherSide: " + otherSide + ", side: " + this.getSide()+"}";
	}
}
