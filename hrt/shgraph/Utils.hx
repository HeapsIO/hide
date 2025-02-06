package hrt.shgraph;
import haxe.macro.Expr;

class ArrayUtils {
	/**
		Returns arr[pos] if key if present, else execute def and puts it into arr[pos]
	**/
	macro public static function getOrPut<V>(arr:ExprOf<Array<V>>, pos:ExprOf<Int>, def:ExprOf<V>):Expr {
		return macro {
			var ___k = ${pos};
			var ___m = ${arr};
			var ___v = ___m[___k];
			if (___v == null) {
				___v = ${def};
				___m[___k] = ___v;
			}
			___v;
		}
	}
}