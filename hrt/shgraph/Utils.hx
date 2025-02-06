package hrt.shgraph;
import haxe.macro.Expr;

class ArrayUtils {
	/**
		Returns arr[pos] if key if present, else execute def and puts it into arr[pos]
	**/
	macro public static function getOrPut<V>(arr:Array<V>, pos:ExprOf<Int>, def:ExprOf<V>):Expr {
		return macro {
			var k = ${pos};
			var m = ${arr};
			var v = m[k];
			if (v == null) {
				v = ${def};
				m[k] = v;
			}
			v;
		}
	}
}