import java.util.Arrays;
public class ShapeManager implements AreaCalculator {
	public static final MeasuringUnit defaultUnit = MeasuringUnit.METERS;
	public Shape[] shapes;
	public ShapeManager (Object[][] values) throws CheckedRuntimeException {
		initShapes(values.length);
		values2Shapes(values);
	}

	public void initShapes(int length) throws CheckedRuntimeException{
		if(length < 0){//should pertain to whole shape heirarchy
			throw new ShapeException("Value is below zero", new IllegalArgumentException());
		}
		this.shapes =  new Shape[length];
	}

	public void setShapes(Shape[] shapes) throws CheckedRuntimeException{
		if(shapes == null){
			throw new ShapeException("Shapes is null", new IllegalArgumentException());//mask that to shape exception
		}
		this.shapes =  shapes;
	}

	public Shape[] getShapes() throws CheckedRuntimeException{
		if(this.shapes == null){
			throw new ShapeException("Shapes is null", new IllegalStateException());//mask that to shape exception
		}
		//shape exception - this.
		return this.shapes;
	}

	public void values2Shapes(Object[][] values) throws CheckedRuntimeException {

		for(int i = 0; i < values.length; i++){
			Object[] value = values[i];
			if(values[i] == null){
				throw new ShapeException("Values inside the array is null", new NullPointerException());
			}
			if(values == null){
				throw new ShapeException("The array is null", new NullPointerException());
			}
			if(i >= values.length){
				throw new ShapeException("The value is beyond the value permitted creating an ArrayIndexOutOfBoundsException", new ArrayIndexOutOfBoundsException());
			}

				// exception for value - shape exception
				//index out of bounds - shape exception
			//arrays cant be null - shape exception - nullpointer excpetion

			switch(value.length){
				case 2:
					shapes[i] = new Square((MeasuringUnit)value[0], (int)value[1]);
					break;
				case 3:
					shapes[i] = new Rectangle((MeasuringUnit)value[0], (int)value[1], (int)value[2]);
				default:
			}
		}
	}
	// the default measuring unit is determined by defaultUnit
	public long convertArea(long area, MeasuringUnit ms) throws CheckedRuntimeException{

		if(ms == null){
			throw new MeasuringUnitException("The Measuring unit is null", new NullPointerException());//should pertain to all  shape hierarchy
		}
		if(ms == MeasuringUnit.METERS){
			area = (long) (area * 3.281);
		}
		if(area > Long.MAX_VALUE){
			throw new AreaCalculatorException("Value is beyond the the data types max value", new ArithmeticException());
		}
		if(area < 0){
			throw new ShapeException("Value is below zero", new IllegalArgumentException());
		}

		return area;
	}

	// the default measuring unit is determined by defaultUnit, use this.getShapes() for sum of the areas
	public long getTotalArea() throws CheckedRuntimeException{
		// this is not complete, it is a hint.//convert area first then do the rest
		long result = 0;
		for(Shape shape: this.getShapes()){
			result += shape.getArea();
			if(result > Long.MAX_VALUE){
				throw new AreaCalculatorException("The value is beyond the data type's max value", new ArithmeticException());
			}
		}
		//calling getArea()

		if(result < 0){
			throw new ShapeException("Value is below zero", new IllegalArgumentException());//change to null pointer exception
		}

		return result;
	}

	// the default measuring unit is determined by defaultUnit, use this.getShapes() for sum of the areas
	public long getTotalArea (MeasuringUnit ms) throws CheckedRuntimeException{
		if(ms == null){
			throw new MeasuringUnitException("The measuring unit is null", new NullPointerException());//measured unit exception for all  Area calculator methods
		}

		long result = 0;
		for(Shape shape: this.getShapes()){
			result += shape.getArea();
		}

		/*if(ms == MeasuringUnit.METERS){
			result = (long) (result * 3.281);
		}*/
		long area = 0;
		if(ms == MeasuringUnit.METERS){
			 area += convertArea( result, ms);//call method

		}

		if(result + area > Long.MAX_VALUE){
			throw new AreaCalculatorException("The value is beyond the data type's max value", new ArithmeticException());
		}
		if(this.getShapes() ==  null){
			throw new ShapeException("The shapes values are null", new NullPointerException());
		}

		return result + area;
	}
}
