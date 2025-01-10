package hrt.animgraph;

import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.Tools;
using Lambda;

class Macros {

	#if macro
	static function getInputsInternal() : Expr {
		var fields = Context.getBuildFields();
		var inputs: Array<Expr> = [];

		for (f in fields) {
			if (f.meta != null && f.meta.find(m -> m.name == ":input") != null) {
				var e : Expr = macro {
					name: $v{f.name},
					type: $e{hrt.animgraph.Macros.getTypeFromField(f)},
				};
				inputs.push(e);
			}
		}

		return macro $a{inputs};
	}

	static function getOutputsInternal() : Expr {
		var fields = Context.getBuildFields();
		var outputs: Array<Expr> = [];

		var inheritAnimNode = false;
		var cl = Context.getLocalClass().get();
		while(cl != null) {
			if (cl.name == "AnimNode") {
				inheritAnimNode = true;
				break;
			}
			cl = cl.superClass?.t.get();
		}

		if (inheritAnimNode && cl.name != "Output" /* Output don't have an anim output ironically */) {
			outputs.push(macro {
				name: "",
				type: Node.OutputType.TAnimation,
			});
		}

		for (f in fields) {
			if (f.meta != null && f.meta.find(m -> m.name == ":output") != null) {
				var e : Expr = macro {
					name: $v{f.name},
					type: $e{hrt.animgraph.Macros.getTypeFromField(f)},
				};
				outputs.push(e);
			}
		}

		return macro $a{outputs};
	}

	static public function getTypeFromField(f: haxe.macro.Expr.Field) : Expr {
		switch (f.kind) {
			case FVar(t, _) : {
				switch (t) {
					case TPath(p):
						if (p.name ==  "AnimNode") {
							return macro hrt.animgraph.Node.OutputType.TAnimation;
						} else if (p.name == "Float") {
							return macro hrt.animgraph.Node.OutputType.TFloat;
						}
						Context.error('Unsupported type ${p}', f.pos, 0);
					default:
						Context.error('Unsupported type for field ${f.name}', f.pos, 0);
					}
				}
			case FProp(_,_,t,_): {
				switch (t) {
					case TPath(p):
						if (p.name ==  "AnimNode") {
							return macro hrt.animgraph.Node.OutputType.TAnimation;
						} else if (p.name == "Float") {
							return macro hrt.animgraph.Node.OutputType.TFloat;
						}
						Context.error('Unsupported type ${p}', f.pos, 0);
					default:
						Context.error('Unsupported type for field ${f.name}', f.pos, 0);
					}
				}
			default:
				Context.error("Must be a var, found " + f.kind, f.pos);
		}
		return null;
	}

	static public function build(doRegister: Bool):Array<Field> {
		var fields = Context.getBuildFields();
		var add = hrt.prefab.Macros.buildSerializableInternal(fields);
		for (a in add) {
			fields.push(a);
		}

		var thisClass = Context.getLocalClass().get();
		var classPath = thisClass.pack.copy();
		classPath.push(thisClass.name);
		var isRoot = thisClass.superClass == null;

		var nodeName = thisClass.meta.extract("name")[0]?.name ?? thisClass.name;
		var inputs : Array<Expr> = [];
		var outputs : Array<Expr>= [];

		fields.push({
			name: "getNameId",
			access: isRoot ? [] : [AOverride],
			kind: FieldType.FFun({
				args: [],
				ret: macro: String,
				expr: macro return $v{nodeName},
			}),
			pos: Context.currentPos(),
		});

		fields.push({
			name: "__inputs",
			access: [AStatic, AFinal],
			kind: FieldType.FVar(
				null,
				hrt.animgraph.Macros.getInputsInternal()
			),
			pos: Context.currentPos(),
		});

		var prevGetInputs = fields.find(f -> f.name == "getInputs");
		if (!isRoot && prevGetInputs != null) {
			Context.error("getInput canno't be manually overriden", prevGetInputs.pos);
		}
		if (!isRoot) {
			fields.push({
				name: "getInputs",
				access: [Access.AOverride],
				kind: FieldType.FFun({
					args: [],
					ret: macro: Array<hrt.animgraph.Node.NodeInputInfo>,
					expr: macro return __inputs,
				}),
				pos: Context.currentPos(),
			});
		}


		fields.push({
			name: "__outputs",
			access: [AStatic, AFinal],
			kind: FieldType.FVar(
				null,
				hrt.animgraph.Macros.getOutputsInternal(),
			),
			pos: Context.currentPos(),
		});

		var prevGetOutputs = fields.find(f -> f.name == "getOutputs");
		if (!isRoot && prevGetOutputs != null) {
			Context.error("getOutputs canno't be manually overriden", prevGetOutputs.pos);
		}
		if (!isRoot) {
			fields.push({
				name: "getOutputs",
				access: [Access.AOverride],
				kind: FieldType.FFun({
					args: [],
					ret: macro: Array<hrt.animgraph.Node.NodeOutputInfo>,
					expr: macro return __outputs,
				}),
				pos: Context.currentPos(),
			});
		}

		var displayName = nodeName;

		#if editor
		if (!isRoot && fields.find(f -> f.name == "getDisplayName") == null) {
			fields.push({
				name: "getDisplayName",
				access: [Access.AOverride],
				kind: FieldType.FFun({
					args: [],
					ret: macro: String,
					expr: macro return $v{displayName},
				}),
				pos: Context.currentPos(),
			});
		}
		#end

		if (doRegister) {

			fields.push({
				name: "_build",
				access: [Access.AStatic],
				kind : FieldType.FVar(macro:Bool, macro hrt.animgraph.Node.register($v{thisClass.name}, ${classPath.toFieldExpr()})),
				pos: Context.currentPos(),
			});
		}
		return fields;
	}

	#end
}