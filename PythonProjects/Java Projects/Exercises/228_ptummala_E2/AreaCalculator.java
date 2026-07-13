public interface AreaCalculator{
	// returns the parameter area from the implementer's default measuring unit to the one given by the unit parameter
	public long convertArea(long area, MeasuringUnit ms)throws CheckedRuntimeException;
	// returns the sum of the areas determined by the implementer from the implementer's default measuring unit to the one given by the unit parameter.
	public long getTotalArea (MeasuringUnit ms) throws CheckedRuntimeException;
	// returns the sum of the areas determined by the implementer using the implementer's default measuring unit
	public long getTotalArea () throws CheckedRuntimeException;
}
