public abstract class Shape {
	private int side;
	protected MeasuringUnit unit;
	public Shape (MeasuringUnit unit, int side) throws CheckedRuntimeException{
		if(unit == null){
			throw new ShapeException("The measuring unit is null", new NullPointerException());//should pertain to all of shape heirarchy
		}
		if(side < 0){
			throw new ShapeException("Value is below zero", new IllegalArgumentException());
		}
		this.unit = unit;
		this.side = side;
	}

	public int getSide(){
		return this.side;
	}

	public MeasuringUnit getMeasuringUnit(){
		return this.unit;
	}

	public abstract int getArea() throws CheckedRuntimeException;
}