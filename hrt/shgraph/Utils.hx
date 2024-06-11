package hrt.shgraph;

class ArrayUtils {
	public static inline function getOrPut<V>(array: Array<V>, pos: Int, def: V) : V {
		var v = array[pos];
		if (v == null) {
			v = def;
			array[pos] = v;
		}
		return v;
	}
}