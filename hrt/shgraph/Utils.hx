package hrt.shgraph;
import hrt.shgraph.AstTools.*;

class MapUtils {
	public static inline function getOrPut<K,V>(map: Map<K,V>, key: K, def: V) : V {
		var v = map.get(key);
		if (v == null) {
			v = def;
			map.set(key,v);
		}
		return v;
	}
}

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