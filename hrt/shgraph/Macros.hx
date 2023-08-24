package hrt.shgraph;

import haxe.macro.Context;
import haxe.macro.Expr;
import hxsl.Ast;
using hxsl.Ast;
using haxe.macro.Tools;

class Macros {
	#if macro
	static function buildNode() {
		var fields = Context.getBuildFields();
		for (f in fields) {
			if (f.name == "SRC") {
				switch (f.kind) {
					case FVar(_, expr) if (expr != null):
						var pos = expr.pos;
						if( !Lambda.has(f.access, AStatic) ) f.access.push(AStatic);
						Context.getLocalClass().get().meta.add(":src", [expr], pos);
						try {
							var c = Context.getLocalClass();

							trace("=========================");
							// function map(e: haxe.macro.Expr) {
							// 	switch(e) {
							// 		case EMeta("sginput", args, e):
							// 			trace("sginput");
							// 	}
							// }

							// expr.map()

							function iter(e: haxe.macro.Expr) : Void {
								switch(e.expr) {
									case EMeta(meta, subexpr):
										if (meta.name == "sginput")
											trace("sginput", subexpr);
										else if (meta.name == "sgoutput")
											trace("sgoutput", subexpr);
									default:
								}
							}

							expr.iter(iter);
							var shader = new hxsl.MacroParser().parseExpr(expr);
							f.kind = FVar(null, macro @:pos(pos) $v{shader});
							var check = new hxsl.Checker();
							check.warning = function(msg,pos) {
								haxe.macro.Context.warning(msg, pos);
							};

							var name = Std.string(c);

							var name = Std.string(c);
							var check = new hxsl.Checker();
							check.warning = function(msg,pos) {
								haxe.macro.Context.warning(msg, pos);
							};
							var shader = check.check(name, shader);
							//trace(shader);
							//Printer.check(shader);
							var str = Context.defined("display") ? "" : hxsl.Serializer.run(shader);
							f.kind = FVar(null, { expr : EConst(CString(str)), pos : pos } );
							f.meta.push({
								name : ":keep",
								pos : pos,
							});
						} catch( e : hxsl.Ast.Error ) {
							fields.remove(f);
							Context.error(e.msg, e.pos);
						}
					default:
				}
			}
		}
		return fields;
	}

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
			kind: FieldType.FVar(macro:Bool, macro ShaderNode.register($v{cl.name}, ${clPath.toFieldExpr()})),
			pos: Context.currentPos(),
		});
		#end

		return fields;
	}
	#end
}