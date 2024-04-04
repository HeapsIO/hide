package hrt.shgraph;

import hxsl.Ast.TExpr;
using hxsl.Ast;
using hrt.shgraph.Utils;
using Lambda;

typedef CacheEntry = {expr: TExpr, inputs: Array<ShaderNode.InputInfo>, outputs: Array<ShaderNode.OutputInfo>, idInputOrder: Map<Int, Int>, idOutputOrder: Map<Int,Int>};

class CustomSerializer extends hxsl.Serializer {

	// we override readvar to remove the allocation of new variable id
	// because we rely on the variable ID to get our custom info about
	// input and outputs
	override function readVar() : TVar {
		var id = readID();
		if( id == 0 )
			return null;
		var v = varMap.get(id);
		if( v != null ) return v;
		v = {
			id : id,
			name : readString(),
			type : null,
			kind : null,
		}
		varMap.set(id, v);
		v.type = readType();
		v.kind = hxsl.Serializer.VKINDS[input.readByte()];
		v.parent = readVar();
		var nq = input.readByte();
		if( nq > 0 ) {
			v.qualifiers = [];
			for( i in 0...nq ) {
				var qid = input.readByte();
				var q = switch( qid ) {
				case 0: var n = input.readInt32(); Const(n == 0 ? null : n);
				case 1: Private;
				case 2: Nullable;
				case 3: PerObject;
				case 4: Name(readString());
				case 5: Shared;
				case 6: Precision(hxsl.Serializer.PRECS[input.readByte()]);
				case 7: Range(input.readDouble(), input.readDouble());
				case 8: Ignore;
				case 9: PerInstance(input.readInt32());
				case 10: Doc(readString());
				case 11: Borrow(readString());
				case 12: Sampler(readString());
				case 13: Final;
				default: throw "assert";
				}
				v.qualifiers.push(q);
			}
		}
		return v;
	}
}

@:autoBuild(hrt.shgraph.Macros.buildNode())
class ShaderNodeHxsl extends ShaderNode {

	static var cache : Map<{}, CacheEntry> = [];

	override public function getInputs() : Array<ShaderNode.InputInfo> {
		var cl = std.Type.getClass(this);
		return cache.getOrPut(cast cl, genCache(cl)).inputs;
	}

	override public function getOutputs() : Array<ShaderNode.OutputInfo> {
		var cl = std.Type.getClass(this);
		return cache.getOrPut(cast cl, genCache(cl)).outputs;
	}

	function genCache(cl: Class<ShaderNodeHxsl>) : CacheEntry {
		var toUnser = (cl:Dynamic).SRC;
		if (toUnser == null) throw "Node " + std.Type.getClassName(cl) + " has no SRC";

		var unser = new CustomSerializer();
		var data = @:privateAccess unser.unserialize(toUnser);

		var expr : TExpr = null;
		for (fn in data.funs) {
			if (fn.ref.name == "fragment") {
				expr = fn.expr;
				break;
			}
		}

		var inputs : Array<ShaderNode.InputInfo> = [];
		var outputs : Array<ShaderNode.OutputInfo> = [];
		var idInputOrder : Map<Int,Int> = [];
		var idOutputOrder : Map<Int,Int> = [];
		var inputCount = 0;
		var outputCount = 0;

		var infos : Map<Int, SgHxslVar> = cast (cl:Dynamic)._variablesInfos;
		for (v in data.vars) {
			var info = infos.get(v.id);
			switch (info) {
				case SgInput(isDynamic, defaultValue):
					inputs.push({name: v.name, type: isDynamic ? SgGeneric(0, ShaderGraph.ConstraintFloat) : typeToSgType(v.type), def: defaultValue});
					idInputOrder.set(v.id, inputCount++);
				case SgOutput(isDynamic):
					outputs.push({name: v.name, type: isDynamic ? SgGeneric(0, ShaderGraph.ConstraintFloat) : typeToSgType(v.type)});
					idOutputOrder.set(v.id, outputCount++);
				case SgConst:
				case null:
			}
		}

		return {expr: expr, inputs: inputs, outputs: outputs, idInputOrder: idInputOrder, idOutputOrder: idOutputOrder};
	}

	override public function generate(ctx: NodeGenContext) : Void {
		var cl = std.Type.getClass(this);
		var cache = cache.getOrPut(cast cl, genCache(cl));

		var infos : Map<Int, SgHxslVar> = cast (cl:Dynamic)._variablesInfos;
		var varsOverride : Map<Int, TExpr> = [];
		var varsRemap : Map<Int, TVar> = [];
		var outputs : Array<TVar> = [];
		var genFailure : Bool = false;

		function patch(e: TExpr) : TExpr {
			switch (e.e) {
				case TVar(v):
					var replacement = varsOverride.get(v.id);
					if (replacement != null)
						return replacement;

					var type = e.t;

					var info = infos.get(v.id);

					switch(info) {
						case SgInput(isDynamic, defaultValue):
							if (isDynamic) {
								type = ctx.getType(SgGeneric(0, ShaderGraph.ConstraintFloat));
							}
							var inputId = cache.idInputOrder.get(v.id);
							replacement = ctx.getInput(inputId);

							// default value handling if we have no input connected
							if (replacement == null) {
								switch (defaultValue) {
									case Const(init):
										replacement = NodeGenContext.convertToType(type, makeFloat(getDef(v.name, init)));
									case Var(name):
										var globalId = Variables.getGlobalNameMap().get(name);
										if (globalId != null) {
											replacement = ctx.getGlobalInput(globalId);
										}
									case null, _:
										genFailure = true;
								}
							}
						case SgConst:
							replacement = makeInt(getConstValue(v.name) ?? 0);
						case SgOutput(_):
							var outputId = cache.idOutputOrder.get(v.id);
							var t = ctx.getType(cache.outputs[outputId].type);

							var outputVar : TVar= {
								name: v.name,
								id: hxsl.Tools.allocVarId(),
								type: t,
								kind: v.kind,
								parent: v.parent,
								qualifiers: v.qualifiers,
							};
							replacement = makeVar(outputVar);
							outputs[outputId] = outputVar;
						case null:
							var tvar = varsRemap.getOrPut(v.id,
							{
								name: v.name,
								id: hxsl.Tools.allocVarId(),
								type: v.type,
								kind: v.kind,
								parent: v.parent,
								qualifiers: v.qualifiers,
							});
							replacement = {e: TVar(tvar), p: e.p, t: e.t};
					}
					if (replacement == null) {
						genFailure = true;
						replacement = e;
					}
					varsOverride.set(v.id, replacement);

					return replacement;
				case TVarDecl(v, init):
					var tvar = varsRemap.getOrPut(v.id,
						{
							name: v.name,
							id: hxsl.Tools.allocVarId(),
							type: v.type,
							kind: v.kind,
							parent: v.parent,
							qualifiers: v.qualifiers,
						});
					return makeExpr(TVarDecl(tvar, if( init != null ) patch(init) else null), e.t);
				case TFor(v, it, loop):
					var tvar = varsRemap.getOrPut(v.id,
						{
							name: v.name,
							id: hxsl.Tools.allocVarId(),
							type: v.type,
							kind: v.kind,
							parent: v.parent,
							qualifiers: v.qualifiers,
						});
					return makeExpr(TFor(tvar, patch(it), patch(loop)), e.t);
				default:
					return e.map(patch);
			}
		}

		var expr = patch(cache.expr);

		if (genFailure) {
			for (outputId => o in cache.outputs) {
				var t = ctx.getType(o.type);
				var expr = NodeGenContext.convertToType(t, makeVec([1.0,0.0,1.0,1.0]));
				ctx.setOutput(outputId, NodeGenContext.convertToType(t, makeVec([1.0,0.0,1.0,1.0])));
				if (outputId == 0) {
					ctx.addPreview(expr);
				}
			}
		}
		else {
			for (outputId => o in cache.outputs) {
				var tvar = outputs[outputId];
				ctx.addExpr(makeExpr(TVarDecl(tvar), tvar.type));
				var expr = makeVar(tvar);
				ctx.setOutput(outputId, expr);
				if (outputId == 0) {
					ctx.addPreview(expr);
				}
			}

			switch(expr.e){
				case TBlock(exprs):
					for (e in exprs) {
						ctx.addExpr(e);
					}
				default:
					throw "function expr is not a block";
			}
		}

	}


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
						var def : SgHxslVar.ShaderDefInput = null;
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

			var classConstVars : Array<String> = cast (cl:Dynamic)._constVars;

			// Const replacement
			for (const in classConstVars) {
				var value = getConstValue(const);
				if (value == null)
					throw "unhandled const value " + const;

				function patchExprConst(expr : TExpr) {
					switch (expr.e) {
						case TVar(v):
							if (v.name == const) {
								expr.e = TConst(CInt(value));
							}
						default:
							expr.map(patchExprConst);
					}
					return expr;
				}
				expr.map(patchExprConst);
			}

			def = {expr: expr, inVars: inVars, outVars: outVars, externVars: externVars, inits: [], functions: funs};
		}

		return def;
	}

	function getConstValue(name: String) : Null<Int> {
		return null;
	}
}