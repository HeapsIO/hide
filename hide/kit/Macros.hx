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
	globalElements: Array<Var>,
	markup: domkit.MarkupParser.Markup,
	outputExprs: Array<Expr>,
};

/**
	TODOS :
	Error reporting position is not accurate (for exemple when assigning to a variable that doesn't exists via attributes)
**/

class Macros {
	/** Used for unit tests to ensure that dml errors are correctly handled **/
	public static macro function testError(dml : Expr, contextObj: Expr, wantedErrorExpr: ExprOf<String>) : Expr {
		var error = "No Error";
		var errorExpr = switch(wantedErrorExpr.expr) {
			case EConst(CString(e, kind)): e;
			default: throw "wantedError must be a string";
		}

		try {
			buildDml(dml, contextObj, macro null);
		} catch (e: domkit.Error) {
			if (e.message == errorExpr) {
				return macro {};
			}
			error = e.message;
		}
		Context.error('Assert error failed, wanted "$errorExpr", got "$error"', dml.pos);
		return macro {};
	}

	public static macro function testNoError(dml : Expr, contextObj: Expr) : Expr {
		try {
			buildDml(dml, contextObj, macro null);
		} catch (e: domkit.Error) {
			Context.error('Assert error failed, wanted no errors, got "${e.message}"', @:privateAccess domkit.Macros.makePos(dml.pos,e.pmin,e.pmax));
			return macro {};
		}
		return macro {};
	}

	#if macro
	public static function build(parentElement: Expr, dml: Expr, ?contextObj: Expr) : Expr {
		try {
			return buildDml(dml, contextObj, parentElement);
		}
		catch (e : domkit.Error) {
			haxe.macro.Context.error(e.message, @:privateAccess domkit.Macros.makePos(dml.pos,e.pmin,e.pmax));
		}
		return macro {};
	}

	static function buildDml(dml: Expr, ?contextObj: Expr, parentElement: Expr) : Expr {
		switch (dml.expr) {
			case EMeta({name :":markup"} ,{expr: EConst(CString(dmlString))}): {
				var parser = new domkit.MarkupParser();
				var pinf = Context.getPosInfos(dml.pos);
				var markup = parser.parse(dmlString, pinf.file, pinf.min).children[0];

				var args : BuildExprArgs = {
					markup: markup,
					outputExprs: [],
					parent: parentElement,
					contextObj: contextObj,
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
				error("dml argument should be a DML Expression", dml.pos.getInfos().min, dml.pos.getInfos().max);
				return null;
		}
	}

	static function makeStringExpr(string: String, pos: Position) : Expr {
		return {expr: EConst(CString(string)), pos: pos};
	}

	static function buildExpr(args: BuildExprArgs) : Void {

		var globalPos = Context.currentPos();
		var pos = makePos(globalPos, args.markup.pmin, args.markup.pmax);

		switch(args.markup.kind) {
			case Node(nodeName): {
				var block: Array<Expr> = [];

				var parentExpr : Expr = args.parent;

				if (nodeName != "root") {
					var elementName = domkit.CssParser.cssToHaxe(nodeName, false);
					var elementPath = "hide.kit." + elementName;

					var elementType = try Context.getType(elementPath) catch(e) {
						error("hide-kit element " + elementPath + " doesn't exist", args.markup.pmin, args.markup.pmax);
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

					var elementPublicId: String = null;
					var fieldLabelAttribute = null;

					var label: ExprOf<String> = null;
					var kitInternalId: ExprOf<String> = null;
					var field: Expr = null;
					var fieldName : String;
					var fieldId : String;

					var fieldsAttributes = [];

					for (attribute in args.markup.attributes ?? []) {
						var valueString : String = null;
						var valueExpr : ExprOf<String> = null;

						switch(attribute.value) {
							case RawValue(s):
								valueString = s;
								valueExpr = makeStringExpr(s,pos);
							case Code(expr):
								var typedExpr = Context.typeExpr(expr);
								if (typedExpr.t.toString() == "String") {
									valueExpr = expr;
								}
								switch (expr.expr) {
									case EConst(CString(s)):
										valueString = s;
									default:
								}
						}

						switch(attribute.name) {
							case "label":
								if (valueExpr == null)
									error("label value must be string expression or a string constant", attribute.pmin, attribute.pmax);
								label = valueExpr;
								fieldsAttributes.push(attribute);
							case "id":
								if (valueString == null)
									error("id value must be a const string", attribute.pmin, attribute.pmax);
								elementPublicId = domkit.CssParser.cssToHaxe(valueString, true);
								if (args.globalElements.find((otherVar) -> otherVar.name == elementPublicId) != null) {
									error("A component with the id " + elementPublicId + " already exists in this build", attribute.pmin, attribute.pmax);
								}
								kitInternalId = makeStringExpr(domkit.CssParser.cssToHaxe(valueString, true), pos);
							case "default":
								// special case for "default" because default is a reserved keyword in haxe
								attribute.name = "defaultValue";
								fieldsAttributes.push(attribute);
							case "field":
								field = switch(attribute.value) {
									case RawValue(v): error("field must be an expression", attribute.pmin, attribute.pmax);
									case Code(v):
										switch(v.expr) {
											case EConst(CIdent(s)):
												v;
											case EField(_, _, _):
												v;
											default:
												error("field must be an identifier expression or a structure field expression", attribute.pmin, attribute.pmax);
										};
								};

								fieldLabelAttribute = {name: "label", value: null, pmin: attribute.pmin, pmax: attribute.pmax, vmin: attribute.vmin};

								var expr = field;
								var fieldPath: Array<String> = [];
								while(expr != null) {
									switch(expr.expr) {
										case EConst(CIdent(s)):
											fieldPath.unshift(s);
											if (fieldName == null)
												fieldName = s;
											break;
										case EField(parentExpr, partName):
											if (fieldName == null)
												fieldName = partName;
											fieldPath.unshift(partName);
											expr = parentExpr;
										default:
											throw "Internal error : field path contain unhandled cases";
									}
								}
								fieldId = fieldPath.join(".");
								if (fieldName == null)
									throw "Internal error : fieldName shouldn't be null";
							default:
								fieldsAttributes.push(attribute);
						}
					}

					if (label == null && field != null) {
						label = makeStringExpr(camelToSpaceCase(fieldName), pos);
						fieldsAttributes.push(fieldLabelAttribute);
						fieldLabelAttribute.value = domkit.MarkupParser.AttributeValue.Code(label);
					}

					if (kitInternalId == null) {
						if (fieldId != null) {
							kitInternalId = makeStringExpr(fieldId, pos);
						}
						if (label != null) {
							kitInternalId = macro @:privateAccess hide.kit.Macros.toInternalIdentifier(${label});
						} else {
							kitInternalId = makeStringExpr('#${elementName}', pos);
						}
					}

					var elementVar : Var;
					var isGlobal = false;
					if (elementPublicId != null) {
						elementVar = {name: elementPublicId, type: elementType.toComplexType(), expr: macro null};
						args.globalElements.push(elementVar);
						isGlobal = true;
					} else {
						elementVar = {name : "element", type: elementType.toComplexType()};
						isGlobal = false;
					}

					var elementExpr : Expr = {expr: EConst(CIdent(elementVar.name)), pos: pos};
					parentExpr = elementExpr;

					var newArguments : Array<Expr> = [];
					newArguments.push(args.parent);
					newArguments.push(kitInternalId);

					for (argumentNo => argument in args.markup.arguments) {
						switch(argument.value) {
							case RawValue(string):
								newArguments.push(makeStringExpr(string, pos));
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
						var fieldName = domkit.CssParser.cssToHaxe(attribute.name, true);
						var fieldExpr : Expr = {expr: EField(elementExpr, fieldName), pos: attributePos};
						var classField = classType.findField(fieldName);

						if (classField == null)
							error("unknown class field " + fieldName, attribute.pmin, attribute.pmax);

						var valueExpr : Expr = switch (attribute.value) {
							case RawValue(string):
								switch(Context.follow(classField.type)) {
									case TAbstract(a, params):
										switch(a.toString())	{
											case "Int":
												var int = Std.parseInt(string);
												if (int == null)
													error('cannot convert "$string" to Int for attribute ${attribute.name}', attribute.pmin, attribute.pmax);
												{expr: EConst(CInt(string)), pos: attributePos};
											case "Float":
												var float = Std.parseFloat(string);
												if (Math.isNaN(float))
													error('cannot convert "$string" to Float for attribute ${attribute.name}', attribute.pmin, attribute.pmax);
												{expr: EConst(CFloat(string)), pos: attributePos};
											case "Bool":
												if (string != "true" && string != "false")
													error('cannot convert "$string" to Bool for attribute ${attribute.name} (must be either "true" or "false")', attribute.pmin, attribute.pmax);
												{expr: EConst(CIdent(string)), pos: attributePos};
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
						var finalExpr = macro @:pos(attributePos) $fieldExpr = $valueExpr;
						block.push(finalExpr);
					}

					if (field != null) {
						// if we have a context object, remap the expression so it's in the form
						// contextObj.path.to.field
						if (!args.contextObj.expr.match(EConst(CIdent("null")))) {
							field = field.map((e) -> {
								switch(e.expr) {
									case EConst(CIdent(s)):
										return {expr: EField(field, s), pos: e.pos}
									default:
										return e;
								}
							});
						}

						block.push(macro @:pos(pos) $elementExpr.value = $field);
						block.push(macro @:pos(pos) @:privateAccess $elementExpr.onFieldChange = (temp:Bool) -> $field = $elementExpr.value);
					}

				}

				var hasChildren = args.markup.children?.length > 0;

				if (hasChildren) {
					var outputExpr: Array<Expr> = [];
					var parentExpr = macro @:pos(pos) var __parent = $parentExpr;
					outputExpr.push(parentExpr);
					for (childIndex => childMarkup in args.markup.children) {
						var childPos = makePos(globalPos, childMarkup.pmin, childMarkup.pmax);

						var childrenArgs : BuildExprArgs = {
							parent: macro @:pos(pos) __parent,
							outputExprs: [],
							markup: childMarkup,
							globalElements: args.globalElements,
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