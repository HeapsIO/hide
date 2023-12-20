package hrt.shgraph;

import hxsl.Ast.TExpr;
using hxsl.Ast;
using Lambda;


@:autoBuild(hrt.shgraph.Macros.buildNode())
class ShaderNodeHxsl extends ShaderNode {

	static var nodeCache : Map<String, ShaderGraph.ShaderNodeDef> = [];

	override public function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>) : ShaderGraph.ShaderNodeDef {
		var cl = std.Type.getClass(this);
		var className = std.Type.getClassName(cl);
		var def = null;//nodeCache.get(className);
		if (def == null) {
			var unser = new hxsl.Serializer();
			var toUnser = (cl:Dynamic).SRC;
			if (toUnser == null) throw "Node " + className + " has no SRC";
			var data = @:privateAccess unser.unserialize(toUnser);
			var expr = null;
			var funs = null;
			for (fun in data.funs) {
				if (fun.ref.name == "fragment")
					expr = fun.expr;
				else {
					if (funs == null)
						funs = new Array<TFunction>();
					funs.push(fun);
				}
			}

			var idToNewId : Map<Int, Int> = [];

			function patchExprId(expr: TExpr) : TExpr {
				switch (expr.e) {
					case TVar(v):
						var newId = idToNewId.get(v.id);
						if (newId == null) {
							newId = getNewIdFn();
							idToNewId.set(v.id, newId);
						}
						v.id = newId;
						return expr;
					default:
						return expr.map(patchExprId);
				}
			}

			patchExprId(expr);

			var inVars : Array<hrt.shgraph.ShaderGraph.ShaderNodeDefInVar>= [];
			var outVars : Array<hrt.shgraph.ShaderGraph.ShaderNodeDefOutVar> = [];
			var externVars = [];

			var classDynamicVal : Array<String> = cast (cl:Dynamic)._dynamicValues;

			for (tvar in data.vars) {
					var input = false;
					var output = false;
					var classInVars : Array<String> = cast (cl:Dynamic)._inVars;
					var classDefVal : Array<String> = cast (cl:Dynamic)._defValues;

					var indexOf = classInVars.indexOf(tvar.name);
					if (indexOf > -1) {
						var defStr = classDefVal[indexOf];
						var def : hrt.shgraph.ShaderGraph.ShaderDefInput = null;
						if (defStr != null) {
							var float = Std.parseFloat(defStr);
							if (!Math.isNaN(float)) {
								def = Const(float);
							} else {
								def = Var(defStr);
							}
						}
						inVars.push({v:tvar, internal: false, defVal: def, isDynamic: classDynamicVal.contains(tvar.name)});
						// TODO : handle default values
						input = true;
					}
					var classOutVars : Array<String> = cast (cl:Dynamic)._outVars;
					if (classOutVars.contains(tvar.name)) {
						outVars.push({v: tvar, internal: false, isDynamic: false});
						output = true;
					}
					if (input && output) {
						throw "Variable is both sginput and sgoutput";
					}
					if (!input && !output) {
						switch (tvar.kind) {
							case Function:
								// do nothing
							default:
								externVars.push(tvar);
						}
					}
			}

			for (v in outVars) {
				if (classDynamicVal.contains(v.v.name)) {
					v.isDynamic = true;
				}
			}

			def = {expr: expr, inVars: inVars, outVars: outVars, externVars: externVars, inits: [], functions: funs};
			nodeCache.set(className, def);
		}

		return def;
	}
}