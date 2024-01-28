package hide.ui;

#if js extern #end class QueryHelper {
	macro public static function J(exprs:Array<haxe.macro.Expr>) {
		return macro new hide.Element($a{exprs});
	}
}