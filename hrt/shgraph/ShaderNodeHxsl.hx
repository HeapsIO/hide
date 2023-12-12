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
						inVars.push({v:tvar, internal: false, defVal: def, isDynamic: false});
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

			var classDynamicVal : Array<String> = cast (cl:Dynamic)._dynamicValues;

			// DynamicType is the smallest vector type or float if all inputTypes are floats
			var dynamicType : Type = null;
			if (inputTypes != null) {
				dynamicType = TFloat;
				for (i => t in inputTypes) {
					var targetInput = inVars[i];
					if (targetInput == null)
						throw "More input types than inputs";
					if (!classDynamicVal.contains(targetInput.v.name))
						continue; // Skip variables not marked as dynamic
					switch (t) {
						case null:
						case TFloat:
							if (dynamicType == null)
								dynamicType = TFloat;
						case TVec(size, t1): // Vec2 always convert to it because it's the smallest vec type
							switch(dynamicType) {
								case TFloat, null:
									dynamicType = t;
								case TVec(size2, t2):
									if (t1 != t2)
										throw "Incompatible vectors types";
									dynamicType = TVec(size < size2 ? size : size2, t1);
								default:
							}
						default:
							throw "Type " + t + " is incompatible with Dynamic";
					}
				}
			}


			for (v in inVars) {
				if (classDynamicVal.contains(v.v.name)) {
					v.v.type = dynamicType;
					if (dynamicType == null)
						v.isDynamic = true;
				}
			}

			for (v in outVars) {
				if (classDynamicVal.contains(v.v.name)) {
					v.v.type = dynamicType;
					if (dynamicType == null)
						v.isDynamic = true;
				}
			}

			def = {expr: expr, inVars: inVars, outVars: outVars, externVars: externVars, inits: [], functions: funs};
			nodeCache.set(className, def);
		}

		return def;
	}
}