public class Square extends Shape{
	public int side;
	public Square (MeasuringUnit unit, int side) throws CheckedRuntimeException{
		super(unit, side);
		this.side = side;//is there an exception that needs to be added to square
		/* if(unit == null){
			throw new ShapeException("", new NullPointerException());
		}*/
	}

	public void setSide(Integer side) throws CheckedRuntimeException{
		this.side = side;
		if(side > 0){
			throw new ShapeException("The value is less than zero", new IllegalStateException());
		}
		//shape exception >0
	}

	public int getArea() throws CheckedRuntimeException{
		int result = 0;
		result += this.side * this.getSide();
		if(result > Integer.MAX_VALUE){
			throw new AreaCalculatorException("The value is beyond the data type's max value", new IllegalArgumentException());
		}
		return result;

	}

	public String toString(){
		return "Square: {_side: " + side + ", side: " + super.getSide()+"}";
	}
}
