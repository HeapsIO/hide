package hrt.texgraph;

import haxe.macro.Context;
import haxe.macro.Expr;
import hxsl.Ast;
using hxsl.Ast;
using haxe.macro.Tools;

class Macros {
	#if macro
	static function autoRegisterNode() {
		var fields = Context.getBuildFields();

		var thisClass = Context.getLocalClass();
		var cl = thisClass.get();
		var clPath = cl.pack.copy();
		clPath.push(cl.name);

		#if editor
		fields.push({
			name: "_",
			access: [Access.AStatic],
			kind: FieldType.FVar(macro:Bool, macro TexNode.register($v{cl.name}, ${clPath.toFieldExpr()})),
			pos: Context.currentPos(),
		});
		#end

		return fields;
	}
	#end
}