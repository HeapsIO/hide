package hide.kit;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Context;
using haxe.macro.Tools;
using haxe.macro.TypeTools;
using Lambda;

typedef BuildExprArgs = {
	parent: Expr,
	contextObj: Expr,
	autoIdCount: Int,
	globalElements: Array<Var>,
	markup: domkit.MarkupParser.Markup,
	outputExprs: Array<Expr>,
};

/**
	TODOS :
	Error reporting position is not accurate (for exemple when assigning to a variable that doesn't exists via attributes)
**/

class Macros {
	#if macro
	public static function build(properties: Expr, dml: Expr, ?contextObj: Expr, ?parentElement: Expr ) : Expr {
		try {
			switch (dml.expr) {
				case EMeta({name :":markup"} ,{expr: EConst(CString(dmlString))}): {
					var parser = new domkit.MarkupParser();
					var pinf = Context.getPosInfos(dml.pos);
					var markup = parser.parse(dmlString, pinf.file, pinf.min).children[0];

					var args : BuildExprArgs = {
						markup: markup,
						outputExprs: [],
						parent: parentElement.expr.match(EConst(CIdent("null"))) ? properties : parentElement,
						contextObj: contextObj,
						autoIdCount: 0,
						globalElements: [],
					}

					buildExpr(args);

					// trick to declare the globalElement variables in the parent scope
					// as one expression
					var initVar : Var = {
						name: "__kit_init",
						expr: macro {
							$b{args.outputExprs};
							true;
						}
					};

					args.globalElements.push(initVar);

					return {expr: EVars(args.globalElements), pos: Context.currentPos()};
				}
				default:
					Context.error("Should be a DML Expression", dml.pos);
					return null;
			}
		}
		catch (e : domkit.Error) {
			haxe.macro.Context.error(e.message, @:privateAccess domkit.Macros.makePos(dml.pos,e.pmin,e.pmax));
		}
		return null;

	}

	static function buildExpr(args: BuildExprArgs) : Void {

		var globalPos = Context.currentPos();
		var pos = makePos(globalPos, args.markup.pmin, args.markup.pmax);

		switch(args.markup.kind) {
			case Node(nodeName): {
				var elementName = kebabToCamelCase(nodeName, true);
				var elementPath = "hide.kit." + elementName;

				var elementType = try Context.getType(elementPath) catch(e) {
					error("hide-kit element " + elementName + " doesn't exist", args.markup.pmin, args.markup.pmax);
					return;
				};

				var constructorArgs = null;
				var classType : ClassType = null;
				switch(elementType) {
					case TInst(classTypeRef, _):
						classType = classTypeRef.get();
						var constructorType : Type = Context.follow(classType.constructor.get().type);

						while(constructorType != null) {
							switch(constructorType) {
								case TFun(funArgs, _):
									constructorArgs = funArgs;
									break;
								default:
									error("couldn't resolve constructor for " + elementPath, args.markup.pmin, args.markup.pmax);
							}
						};
					default:
						error("type " + elementPath + " is not a class", args.markup.pmin, args.markup.pmax);
				}

				var kitId: String = null;
				var codeId: String = null;
				var label: String = null;
				var field: String = null;
				var fieldLabelAttribute = null;

				var fieldsAttributes = [];

				for (attribute in args.markup.attributes ?? []) {
					var valueString = switch(attribute.value) {
						case RawValue(s): s;
						default:
							null;
					}

					switch(attribute.name) {
						case "label":
							if (valueString == null)
								error("label value must be a const string", attribute.pmin, attribute.pmax);
							label = valueString;
							fieldsAttributes.push(attribute);
						case "id":
							if (valueString == null)
								error("id value must be a const string", attribute.pmin, attribute.pmax);
							codeId = kebabToCamelCase(valueString);
							if (args.globalElements.find((otherVar) -> otherVar.name == codeId) != null) {
								error("A component with the id " + codeId + " already exists in this build", attribute.pmin, attribute.pmax);
							}
							kitId = kebabToCamelCase(valueString);
						case "field":
							field = switch(attribute.value) {
								case RawValue(v): error("field must be an expression", attribute.pmin, attribute.pmax);
								case Code(v):
									switch(v.expr) {
										case EConst(CIdent(s)):
											s;
										default:
											error("field must be an identifier expression", attribute.pmin, attribute.pmax);
									};
							};
							fieldLabelAttribute = {name: "label", value: domkit.MarkupParser.AttributeValue.RawValue(field), pmin: attribute.pmin, pmax: attribute.pmax, vmin: attribute.vmin};

							var isNull = args.contextObj.expr.match(EConst(CIdent("null")));
							if (isNull)
								error("contextObj must be not null for `field` to work", attribute.pmin, attribute.pmax);

							var contextTyped = Context.typeExpr(args.contextObj);
							var contextType = Context.follow(contextTyped.t);
							switch(contextType) {
								case TInst(classType, _):
									var classField = classType.get().findField(field);
									if (classField == null)
										error("contextObj doesn't have a field named " + field, attribute.pmin, attribute.pmax);
								case TDynamic(t):
								default:
									error("contextObj must be a dynamic or a class instance for field to work (got " + contextType.toString() + ")", attribute.pmin, attribute.pmax);
							}
						default:
							fieldsAttributes.push(attribute);
					}
				}

				if (label == null && field != null) {
					label = camelToSpaceCase(field);
					fieldsAttributes.push(fieldLabelAttribute);
					fieldLabelAttribute.value = domkit.MarkupParser.AttributeValue.RawValue(label);
				}

				if (kitId == null) {
					if (label != null) {
						kitId = toInternalIdentifier(label);
					} else {
						kitId = '#${args.autoIdCount}';
						args.autoIdCount += 1;
					}
				}

				var elementVar : Var;
				var isGlobal = false;
				if (codeId != null) {
					elementVar = {name: codeId, type: elementType.toComplexType()};
					args.globalElements.push(elementVar);
					isGlobal = true;
				} else {
					elementVar = {name : "element", type: elementType.toComplexType()};
					isGlobal = false;
				}

				var elementExpr : Expr = {expr: EConst(CIdent(elementVar.name)), pos: pos};

				var block: Array<Expr> = [];

				var newArguments : Array<Expr> = [];
				newArguments.push(args.parent);
				newArguments.push({expr: EConst(CString(kitId)), pos: pos});

				for (argumentNo => argument in args.markup.arguments) {
					switch(argument.value) {
						case RawValue(string):
							newArguments.push({expr: EConst(CString(string)), pos: pos});
						case Code(haxeExpr):
							newArguments.push(haxeExpr);
					}
				}


				var newExpr : Expr = {expr: ENew(@:privateAccess TypeTools.toTypePath(classType, []), newArguments), pos: pos};
				if (!isGlobal) {
					var e = macro parent = $newExpr;
					block.push({expr: EVars([elementVar]), pos: pos});
				}
				block.push({expr: EBinop(OpAssign, elementExpr, newExpr), pos: pos});


				for (attribute in fieldsAttributes) {
					var attributePos = makePos(globalPos, attribute.pmin, attribute.pmax);
					var field : Expr = {expr: EField(elementExpr, attribute.name), pos: attributePos};
					var classField = classType.findField(attribute.name);

					var valueExpr : Expr = switch (attribute.value) {
						case RawValue(string):
							if (classField == null)
								error("unknown class field " + attribute.name, attribute.pmin, attribute.pmax);
							switch(Context.follow(classField.type)) {
								case TAbstract(a, params):
									switch(a.toString())	{
										case "Int":
											{expr: EConst(CInt(string)), pos: attributePos};
										case "Float":
											{expr: EConst(CFloat(string)), pos: attributePos};
										case "Bool":
											{expr: EConst(CIdent(string == "false" ? "false" : "true")), pos: attributePos};
										default:
											error("unhandeld abstract " + a.toString(), attribute.pmin, attribute.pmax);
									}
								case TInst(type, _):
									switch(type.toString()) {
										case "String":
											{expr: EConst(CString(string)), pos: attributePos};
										default:
											error("unhandeld inst " + type.toString(), attribute.pmin, attribute.pmax);
									}
								default:
									error("can't convert "  + string + '(${attribute.name} -> ${classField.type})  to ' + classField.type.toString(), attribute.pmin, attribute.pmax);
							};
						case Code(haxeExpr):
							haxeExpr;
						case null:
							{expr: EConst(CIdent("true")), pos: attributePos};
					};
					var finalExpr = macro @:pos(attributePos) $field = $valueExpr;
					block.push(finalExpr);
				}

				if (field != null) {
					block.push(macro @:pos(pos) $elementExpr.value = ${args.contextObj}.$field);
					block.push(macro @:pos(pos) $elementExpr.onValueChange = function(temp:Bool) {${args.contextObj}.$field = $elementExpr.value;});
				}

				var hasChildren = args.markup.children?.length > 0;

				if (hasChildren) {
					var outputExpr: Array<Expr> = [];
					var parentExpr = macro @:pos(pos) var __parent = $elementExpr;
					outputExpr.push(parentExpr);
					for (childIndex => childMarkup in args.markup.children) {
						var childPos = makePos(globalPos, childMarkup.pmin, childMarkup.pmax);

						var childrenArgs : BuildExprArgs = {
							parent: macro @:pos(pos) __parent,
							outputExprs: [],
							markup: childMarkup,
							globalElements: args.globalElements,
							autoIdCount: childIndex,
							contextObj: args.contextObj,
						};

						buildExpr(childrenArgs);

						outputExpr.push({expr: EBlock(childrenArgs.outputExprs), pos: childPos});
					}

					block.push({expr: EBlock(outputExpr), pos: pos});
				}

				var finalBlock = {expr: EBlock(block), pos: pos};
				var finalExpr : Expr = if (args.markup.condition != null) {
					{expr: EIf(args.markup.condition.cond, finalBlock, null), pos: pos};
				} else {
					finalBlock;
				}
				args.outputExprs.push(finalExpr);
			}
			default:
				error("unhandled", args.markup.pmin, args.markup.pmax);
		}
	}

	static function makePos( p : Position, pmin : Int, pmax : Int ) {
		var p0 = Context.getPosInfos(p);
		return Context.makePosition({ min : pmin, max : pmax, file : p0.file });
	}
	#end

	static function kebabToCamelCase(str: String, pascalCase: Bool = false) : String {
		var wasDash = pascalCase;
		var finalString = "";
		for (charIndex in 0...str.length) {
			var char = str.charAt(charIndex);
			if (char == "-") {
				wasDash = true;
				continue;
			}
			if (wasDash) {
				finalString += char.toUpperCase();
			} else {
				finalString += char;
			}
			wasDash = false;
		}
		return finalString;
	}

	static function camelToSpaceCase(str:String):String {
		var wasCap = false;
		var finalString = "";
		for (charIndex in 0...str.length) {
			var char = str.charAt(charIndex);

			if (charIndex == 0) {
				finalString += char.toUpperCase();
				wasCap = true;
				continue;
			}

			var isCap = (char.toUpperCase() == char);

			if (isCap && !wasCap) {
				finalString += " ";
			}

			if (isCap && wasCap) {
				finalString += char.toUpperCase();
				continue;
			}

			finalString += char;

			wasCap = isCap;
		}
		return finalString;
	}

	static function toInternalIdentifier(str: String) : String {
		var finalString = "";
		for (charIndex in 0...str.length) {
			var char = str.charAt(charIndex).toLowerCase();
			var charCode = char.charCodeAt(0);
			if ((charCode >= "a".code && charCode <= "z".code) ||
				 (charCode >= "0".code && charCode <= "9".code) ||
				 (charCode == "-".code) ||
				 (charCode == "_".code)) {
				finalString += char;
			} else {
				finalString += "_";
			}
		}
		return finalString;
	}

	public static function makeTypePath( t : BaseType ) {
		var path = t.module.split(".");
		if( t.name != path[path.length-1] ) path.push(t.name);
		return path;
	}

	static function error( msg : String, pmin : Int, pmax : Int = -1 ) : Dynamic {
		throw new domkit.Error(msg, pmin, pmax);
	}
}