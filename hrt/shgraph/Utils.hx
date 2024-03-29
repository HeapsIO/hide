package hrt.shgraph;


class Utils {
	public static inline function getOrPut<K,V>(map: Map<K,V>, key: K, def: V) : V {
		var v = map.get(key);
		if (v == null) {
			v = def;
			map.set(key,v);
		}
		return v;
	}
}