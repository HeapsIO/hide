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

							// function map(e: haxe.macro.Expr) {
							// 	switch(e) {
							// 		case EMeta("sginput", args, e):
							// 			trace("sginput");
							// 	}
							// }

							// expr.map()

							var varmap : Map<String, hrt.shgraph.SgHxslVar> = [];

							function iter(e: haxe.macro.Expr) : Void {
								switch(e.expr) {
									case EMeta(meta, subexpr):
										switch (meta.name) {
											case "sginput":
												var defValue : hrt.shgraph.SgHxslVar.ShaderDefInput = null;
												if (meta.params != null && meta.params.length > 0) {
													switch (meta.params[0].expr) {
														case EConst(v):
															switch(v) {
																case CIdent(name):
																	defValue = Var(name);
																case CString(val):
																	defValue = Var(val);
																case CFloat(val), CInt(val):
																	defValue = Const(Std.parseFloat(val));
																default:
																	throw "sginput default param must be an identifier or a integer";
															}
														default:
															trace(meta.params[0].expr);
															throw "sginput default param must be a constant value";
													}
												}

												switch(subexpr.expr) {
													case EVars(vars):
														for (v in vars) {
																var isDynamic = false;
																switch (v.type) {
																	case TPath(p) if (p.name == "Dynamic"):
																		isDynamic = true;
																		p.name = "Vec4"; // Convert dynamic value back to vec4 as a hack
																	default:
																}
																varmap.set(v.name, SgInput(isDynamic, defValue));
															}
															e.expr = subexpr.expr;
													default:
														throw "sginput must be used with variables only";
												}
											case "sgoutput":
												switch(subexpr.expr) {
													case EVars(vars):
														for (v in vars) {
															var isDynamic = false;
															switch (v.type) {
																case TPath(p) if (p.name == "Dynamic"):
																	isDynamic = true;
																	p.name = "Vec4"; // Convert dynamic value back to vec4 as a hack
																default:
															}

															varmap.set(v.name, SgOutput(isDynamic));
														}
														e.expr = subexpr.expr;
													default:
														throw "sgoutput must be used with variables only";
												}
											case "sgconst":
												switch(subexpr.expr) {
													case EVars(vars):
														for (v in vars) {
															varmap.set(v.name, SgConst);
														}
														e.expr = subexpr.expr;
													default:
														throw "sgconst must be used with variables only";
												}
											default:
										}
									default:
								}
							}

							expr.iter(iter);
							var shader = new hxsl.MacroParser().parseExpr(expr);
							f.kind = FVar(null, macro @:pos(pos) $v{shader});
							var name = Std.string(c);

							var check = new hxsl.Checker();
							check.warning = function(msg,pos) {
								haxe.macro.Context.warning(msg, pos);
							};

							check.loadShader = loadShader;

							var shader = check.check(name, shader);
							//trace(shader);
							//Printer.check(shader);
							var serializer = new hxsl.Serializer();
							var str = Context.defined("display") ? "" : serializer.serialize(shader);
							f.kind = FVar(null, { expr : EConst(CString(str)), pos : pos } );
							f.meta.push({
								name : ":keep",
								pos : pos,
							});

							function makeField(name: String, arr: Array<String>) : Field
							{
								return {
									name: name,
									access: [APublic, AStatic],
									kind: FVar(macro : Array<String>, macro $v{arr}),
									pos: f.pos,
									meta: [{
											name : ":keep",
											pos : pos,}
									],
								};
							}

							var finalMap : Map<Int, hrt.shgraph.SgHxslVar> = [];

							for (v in shader.vars) {
								var info = varmap.get(v.name);
								if (info != null) {
									var serId = @:privateAccess serializer.idMap.get(v.id);
									finalMap.set(serId, info);
								}
							}

							fields.push(
							{
								name: "_variablesInfos",
								access: [APublic, AStatic],
								kind: FVar(macro : Map<Int, hrt.shgraph.SgHxslVar>, macro $v{finalMap}),
								pos: f.pos,
								meta: [{
										name : ":keep",
										pos : pos,}
								],
							}
							);


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

	static function loadShader( path : String ) {
		var m = Context.follow(Context.getType(path));
		switch( m ) {
		case TInst(c, _):
			var c = c.get();
			for( m in c.meta.get() )
				if( m.name == ":src" )
					return new hxsl.MacroParser().parseExpr(m.params[0]);
		default:
		}
		throw path + " is not a shader";
		return null;
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