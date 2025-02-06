package hrt.tools;
import haxe.macro.Expr;

class MapUtils {
	/**
		Returns map[key] if key if present, else execute def and puts it into map[key]
	**/
	macro public static function getOrPut<K, V>(map:ExprOf<Map<K, V>>, key:ExprOf<K>, def:ExprOf<V>):Expr {
		return macro {
			var k = ${key};
			var m = ${map};
			var v = m.get(k);
			if (v == null) {
				v = ${def};
				m.set(k, v);
			}
			v;
		}
	}
}