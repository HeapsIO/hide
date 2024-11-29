package hrt.animgraph;

import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.Tools;
using Lambda;

class Macros {

	macro function getInputs() : ExprOf<Array<hrt.animgraph.Node.NodeInputInfo>> {
		return getInputsInternal();
	}

	macro function getOutputs() : ExprOf<Array<hrt.animgraph.Node.NodeOutputInfo>> {
		return getOutputsInternal();
	}

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
			case FVar(t, _):
				var typeName = haxe.macro.ComplexTypeTools.toString(t);
				if (typeName == "h3d.anim.Animation") {
					return macro hrt.animgraph.Node.OutputType.TAnimation;
				}
				else if (typeName == "Float") {
					return macro hrt.animgraph.Node.OutputType.TFloat;
				}
				else {
					Context.error('Unsupported type ${typeName}', f.pos, 0);
				}
			default:
				Context.error('@:input must be a var', f.pos, 0);
		}
		return null;
	}

	static public function build(doRegister: Bool):Array<Field> {
		var fields = Context.getBuildFields();
		var add = hrt.prefab.Macros.buildSerializableInternal(fields);
		for (a in add) {
			fields.push(a);
		}

		#if editor
		var thisClass = Context.getLocalClass().get();
		var classPath = thisClass.pack.copy();
		classPath.push(thisClass.name);
		var isRoot = thisClass.superClass == null;

		var nodeName = thisClass.meta.extract("name")[0]?.name ?? thisClass.name;
		var inputs : Array<Expr> = [];
		var outputs : Array<Expr>= [];

		for (f in fields) {
			if (f.meta.find(m -> m.name == ":input") != null) {
				var e : Expr = macro {
					name: $v{f.name},
					type: $e{getTypeFromField(f)},
				};
				inputs.push(e);
			}
			if (f.meta.find(m -> m.name == ":output") != null) {
				var e : Expr = macro {
					name: $v{f.name},
					type: $e{getTypeFromField(f)},
				};
				outputs.push(e);
			}
		}

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

		if (fields.find(f -> f.name == "getInputs") == null) {
			var inputExpr = hrt.animgraph.Macros.getInputsInternal();

			fields.push({
				name: "getInputs",
				access: [Access.AOverride],
				kind: FieldType.FFun({
					args: [],
					ret: macro: Array<hrt.animgraph.Node.NodeInputInfo>,
					expr: macro return ${inputExpr},
				}),
				pos: Context.currentPos(),
			});
		}

		if (fields.find(f -> f.name == "getOutputs") == null) {
			var outputExpr = hrt.animgraph.Macros.getOutputsInternal();

			fields.push({
				name: "getOutputs",
				access: [Access.AOverride],
				kind: FieldType.FFun({
					args: [],
					ret: macro: Array<hrt.animgraph.Node.NodeOutputInfo>,
					expr: macro return ${outputExpr},
				}),
				pos: Context.currentPos(),
			});
		}

		var displayName = nodeName;

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

		if (doRegister) {
			var inputs = hrt.animgraph.Macros.getInputsInternal();
			var outputExpr = hrt.animgraph.Macros.getOutputsInternal();

			fields.push({
				name: "_build",
				access: [Access.AStatic],
				kind : FieldType.FVar(macro:Bool, macro hrt.animgraph.Node.register($v{thisClass.name}, ${classPath.toFieldExpr()})),
				pos: Context.currentPos(),
			});
		}
		#end
		return fields;
	}

	#end
}