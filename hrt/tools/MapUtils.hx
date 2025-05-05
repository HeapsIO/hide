package hrt.tools;
import haxe.macro.Expr;

class MapUtils {
	/**
		Returns `map[key]` if key if present, else evaluate `def` and puts the result into `map[key]`, then retunrs `map[key]`
	**/
	macro public static function getOrPut<K, V>(map:ExprOf<Map<K, V>>, key:ExprOf<K>, def:ExprOf<V>):Expr {
		return macro {
			var ___k = ${key};
			var ___m = ${map};
			var ___v = ___m.get(___k);
			if (___v == null) {
				___v = ${def};
				___m.set(___k, ___v);
			}
			___v;
		}
	}
}