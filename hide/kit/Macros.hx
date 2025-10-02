package hide.kit;
import haxe.macro.Expr;

class Macros {
	public static macro function build(property: ExprOf<hide.kit.Properties>, dml: Expr, contextObj: ExprOf<Dynamic>) : Expr {
		#if !macro
		switch (dml.expr) {
			case EConst(CString(str)): {
				var parser = new domkit.MarkupParser();
				var pinf = Context.getPosInfos(dml.pos);
				var markup = parser.parse(string, pinf.file, pinf.min);
				trace(markup);
			}
			default:
				Context.error("Failed to load domkit source", dml.pos);
		}
		#end
		return macro trace("hello");
	}
}