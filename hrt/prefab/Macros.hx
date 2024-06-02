package hrt.prefab;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.ExprTools;

using Lambda;


class Macros {

	public static macro function getSerializableProps() : Expr {

		var serializableProps = [];
		var clRef = Context.getLocalClass();
		if (clRef == null)
			throw 'no class';
		var cl : ClassType = clRef.get();

		while (cl != null) {
			var fields = cl.fields.get();
			for (f in fields) {
				if (f.meta.has(":s")) {
					serializableProps.push(f);
				}
			}
			if (cl.superClass != null) {
				cl = cl.superClass.t.get();
			} else {
				break;
			}
		}

		var serArrayExprs = [
			for (f in serializableProps) {
				var props : Array<ObjectField> = [];
				props.push({
					field: "name",
					expr: macro $v{f.name},
				});

				var meta : Array<ObjectField> = [];

				if (f.doc != null) {
					meta.push({
						field: "doc",
						expr: macro $v{f.doc},
					});
				}

				var ranges = f.meta.extract(":range");
				if (ranges.length > 0) {
					var range = ranges[0];
					if (range.params.length > 0) {
						meta.push({
							field: "range_min",
							expr: range.params[0],
						});
					}
					if (range.params.length > 1 ) {
						meta.push({
							field: "range_max",
							expr: range.params[1],
						});
					}
					if (range.params.length > 2 ) {
						meta.push({
							field: "range_step",
							expr: range.params[2],
						});
					}
				}

				props.push({
					field: "meta",
					expr: {
						expr: EObjectDecl(meta),
						pos: Context.currentPos(),
					}
				});


				var hasSetter = false;
				switch(f.kind) {
					case FVar(_, AccCall):
						hasSetter = true;
					default:
				};

				props.push({
					field: "hasSetter",
					expr: macro $v{hasSetter},
				});

				var e : Expr = macro @:pos(f.pos) null;
				if (f.expr() != null) {
					e = Context.getTypedExpr(f.expr());
				}
				var defVal = e.expr.match(EConst(_) | EBinop(_) | EUnop(_)) ? e : macro @:pos(f.pos) null;

				props.push({
					field: "defaultValue",
					expr: macro ($defVal:Dynamic),
				});

				{
					expr: EObjectDecl(props),
					pos: Context.currentPos(),
				}
			}
		];

		return macro $a{serArrayExprs};
	}

	public static macro function Cast(e : Expr, typeToCast : String) : Expr {
		return macro Std.downcast(${e}, $i{typeToCast});
	}

	public static function enumOrNullByName<T>(e:Enum<T>, constr:String, ?params:Array<Dynamic>, ?defValue:T):T {
		var value = try {
			haxe.EnumTools.createByName(e, constr, params);
		} catch (_) {
			null;
		};

		if (value == null) {
			if (defValue != null)
				value = defValue;
			else {
				var defaultConstructors = std.Type.allEnums(e);
				if (defaultConstructors.length > 0) value = defaultConstructors[0];
			}
		}

		return value;
	}

	static function tryCopyInst(cl : Ref<ClassType>, params : Array<Type>, funcName : String, source : Expr) : Null<Expr> {
		switch(cl.toString()){
			case "Array" | "String":
				return null;
			default:
				var name = cl.get().pack.copy();
				name.push(cl.get().name);
				return macro {
					if ($e{source} != null) {
						var tmp = std.Type.createEmptyInstance($p{name});
						@:privateAccess tmp.$funcName($e{source});
						tmp;
					}
					else {
						null;
					}
				}
		}
	}

	static macro public function deepCopyFromDynamic(target: Expr, sourceExpr: Expr, defaultValue: Expr) : Expr {
		var type = Context.typeof(target);

		function custommFilter(type:Type, source:Expr, sourceType:Type, defaultValue: Expr) : Expr {
			switch (type) {
				// Fixup string to enum
				case TEnum(t, _):
					var path = t.get().pack.copy();
					path.push(t.get().name);
					if (defaultValue == null)
						defaultValue = macro @:pos(source.pos) null;
					return macro @:pos(source.pos) {
						if (Std.isOfType($e{source}, String) || $e{source} == null) {
							hrt.prefab.Macros.enumOrNullByName($p{path}, $e{source}, null, $e{defaultValue});
						} else {
							$e{source};
						}
					}
				case TInst(cl, params):
					return tryCopyInst(cl, params, "copyFromDynamic", source);
				default:
					return null;
			}
		}

		var e : Expr = deepCopyRec(type, sourceExpr, Context.typeof(sourceExpr), defaultValue, custommFilter);

		var pos = Context.currentPos();

		return macro @:pos(pos) $e{target} = ${e};
	};

	static macro public function deepCopyFromOther(target: Expr, sourceExpr: Expr, defaultValue: Expr) : Expr {
		var type = Context.typeof(target);

		function custommFilter(type:Type, source:Expr, sourceType:Type, defaultValue: Expr) : Expr {
			switch (type) {
				case TInst(cl, params):
					return tryCopyInst(cl, params, "copyFromOther", source);
				default:
					return null;
			}
		}

		var e : Expr = deepCopyRec(type, sourceExpr, Context.typeof(sourceExpr), defaultValue, custommFilter);

		var pos = Context.currentPos();

		return macro @:pos(pos) $e{target} = ${e};
	};

	static macro public function deepCopyToDynamic(target: Expr, sourceExpr: Expr, defaultValue: Expr) : Expr {
		var type = Context.typeof(sourceExpr);

		// Transform enum -> strings for json
		function custommFilter(type:Type, source:Expr, sourceType:Type, defaultValue: Expr) : Expr {
			switch (sourceType) {
				case TEnum(t, _):
					return macro haxe.EnumTools.EnumValueTools.getName($e{source});
				case TInst(cl, params):
					switch(cl.toString()){
						case "Array" | "String":
							return null;
						default:
							var name = cl.get().pack.copy();
							name.push(cl.get().name);
							return macro {
								if ($e{source} != null) {
									@:privateAccess $e{source}.copyToDynamic({});
								}
								else {
									null;
								}
							}
					}
				default:
					return null;
			}
		}

		var e : Expr = deepCopyRec(type, sourceExpr, Context.typeof(sourceExpr), null, custommFilter);
		var pos = Context.currentPos();
		return macro @:pos(pos) if ($e{shouldSerializeValule(Context.typeof(sourceExpr), sourceExpr, defaultValue)}) $e{target} = ${e};
	}

	#if macro

	static function shouldSerializeValule(type: Type, a: Expr, b: Expr) : Expr {
		switch (type) {
			case TInst(cl, params):
				switch(cl.toString()){
					case "Array":
						return macro @:pos(a.pos) $a.length > 0;
					}
			case TType(subtype, _):
				return shouldSerializeValule(subtype.get().type, a, b);
			default:
		}
		return macro @:pos(a.pos) ${a} != ${b};
	}

	static public function getDefValueForType(t : Type) {
		return switch(t) {
			case TAbstract(t, c):
				var n = t.get().name;
				switch(n) {
					case "Int"|"Float": macro 0;
					case "Bool": macro false;
					default: macro null;
				}
			default:
				macro null;
		}
	}

	static public function buildPrefab() {
		var buildFields = Context.getBuildFields();

		var typeName = Context.getLocalClass().get().name;


		var loadField = null;
		var copyField = null;
		for (f in buildFields) {
			if (f.name == "copy") {
				copyField = f;
			}
			if (f.name == "load") {
				loadField = f;
			}
		}

		if (loadField != null && copyField == null) {
			Context.error("Prefab \"" + typeName + "\" overrides load without overriding copy (data will be not properly initialized when cloning the prefab)", loadField.pos);
		}


		var getSerFunc : Function = {
			args: [],
			expr: macro {
				if (serializablePropsFields == null)
					serializablePropsFields = hrt.prefab.Macros.getSerializableProps();
				return serializablePropsFields;
			},
		};

		buildFields.push({
			name: "serializablePropsFields",
			access: [AStatic],
			kind: FVar(macro : Array<hrt.prefab.Prefab.PrefabField>, macro null),
			pos: Context.currentPos(),
		});

		var serFieldField : Field = {
			name: "getSerializablePropsStatic",
			doc: "Returns the list of props that have the @:s meta tag associated to them in this prefab type",
			access: [AStatic, APublic],
			kind: FFun(getSerFunc),
			pos: Context.currentPos(),
		}

		buildFields.push(serFieldField);



		for (f in buildFields) {
			if (f.name == "make") {
				f.name = "__makeInternal";
				f.meta.push({name: ":noCompletion", pos:Context.currentPos()});
			}
		}

		function classExtends(t: haxe.macro.Type.ClassType, name: String) {
			if (t == null)
				return false;
			if (t.name == name) {
				return true;
			}
			return classExtends(t.superClass?.t.get(), name);
		}

		var localClass = Context.getLocalClass().get();

		var sharedRootInit = macro {};
		if (classExtends(localClass, "Object3D")) {
			sharedRootInit = macro if (shared.root3d == null) @:privateAccess shared.root3d = shared.current3d = new h3d.scene.Object();
		}
		else if (classExtends(localClass, "Object2D")) {
			sharedRootInit = macro if (shared.root2d == null) @:privateAccess shared.root2d = shared.current2d = new h2d.Object();
		}

		var expr = macro {
			if (shared == sh) sh = null;
			if (sh != null || !this.shared.isInstance) return cast makeClone(sh);
			if (!this.shouldBeInstanciated())
				return this;
			$e{sharedRootInit};
			return cast __makeInternal();
		}

		var make : Function = {
			args: [
				{ name : "sh", type : macro : hrt.prefab.Prefab.ContextMake, opt: true}
			],
			expr: expr,
			ret: haxe.macro.TypeTools.toComplexType(Context.getLocalType()),
		}

		var access = [APublic];
		if (typeName != "Prefab")
			access.push(AOverride);

		buildFields.push({
			name: "make",
			access : access,
			pos : Context.currentPos(),
			kind: FFun(make)
		});



		var buildFields2 = buildSerializableInternal(buildFields);
		for (f in buildFields2) {
			buildFields.push(f);
		}

		replaceNew(buildFields);

		return buildFields;
	}

	static public function replaceNew(fields: Array<Field>) {
		final newName = "__newInit";
		var localClass = Context.getLocalClass().get();
		var isRoot = localClass.superClass == null;

		var newReplaced = false;
		for (f in fields) {
			if (f.name == "new") {
				newReplaced = true;
				f.name = newName;
				if (!isRoot) {
					f.access = f.access ?? [];
					if (!f.access.contains(AOverride))
						f.access.push(AOverride);
				}

				f.meta = f.meta ?? [];
				if (f.meta.find((m) -> m.name == ":noCompletion") == null) {
					f.meta.push({name: ":noCompletion", pos:Context.currentPos()});
				}

				switch (f.kind) {
					case FFun(func): {
						function rec(e: Expr){
							switch (e.expr) {
								case ECall(subE = {expr: EConst(CIdent("super"))}, _):
									subE.expr = EField({pos:e.pos, expr: EConst(CIdent("super"))}, newName);
								case _:
									ExprTools.iter(e, rec);
							}
						};
						ExprTools.iter(func.expr, rec);

						//trace(ExprTools.toString(func.expr));
					}
					default:
						throw "new is not a function";
				}
			}
		}

		if (newReplaced) {
			var newExpr = null;
			var access = [APublic];
			if (isRoot) {
				newExpr = macro {
					this.$newName(parent, contextShared);
				};
			}
			else {
				access.push(AOverride);
				newExpr = macro {
					super(parent, contextShared);
				};
			}

			var newDecl : Field = {
				name: "new",
				access: access,
				kind: FFun({args:[
					{name: "parent", type: {macro: hrt.prefab.Prefab;}},
					{name: "contextShared", type: {macro: hrt.prefab.ContextShared;}},
				],expr: newExpr}),
				pos: Context.currentPos(),
			}

			fields.push(newDecl);
		}
	}

	static public function buildSerializable() {
		var buildFields = Context.getBuildFields();
		var ser = buildSerializableInternal(buildFields);
		for (f in ser) {
			buildFields.push(f);
		}
		return buildFields;
	}
	static public function buildSerializableInternal(fields: Array<Field>) {
		var thisClass = Context.getLocalClass();
		var isRoot = thisClass.get().superClass == null;
		var buildFields = fields;

		var serializableFields = [];
		var copyableFields = [];
		var cloneInitFields : Array<Field> = [];
		var pos = Context.currentPos();


		for (f in buildFields) {
			if (f.meta == null)
				continue;

			var isSerializable = false;
			var isDeepCopy = false;
			var isCopyable = false;
			for (m in f.meta) {
				switch(m.name) {
					case ":s":
						isSerializable = true;
					case ":c":
						isCopyable = true;
					case ":deepCopy":
						isDeepCopy = true;
				}
			}

			if (isSerializable) {
				serializableFields.push({field: f, deepCopy: isDeepCopy});
			}

			if (isCopyable || isSerializable) {
				copyableFields.push({field: f, deepCopy: isDeepCopy});
			}

			if (!isSerializable && !isDeepCopy && !isCopyable) {
				cloneInitFields.push(f);
			}
		}

		var copyFromDynamic : Array<Expr> = [];
		var copyFromOther : Array<Expr> = [];
		var copyToDynamic : Array<Expr> = [];

		var root = thisClass;
		while(root.get().superClass != null) {
			root = root.get().superClass.t;
		}

		var rootPath = root.get().pack.copy();
		rootPath.push(root.get().name);

		if( !isRoot ) {
			copyFromDynamic.push(macro @:pos(pos) super.copyFromDynamic(obj));
			copyFromOther.push(macro @:pos(pos) super.copyFromOther(obj));
			copyToDynamic.push(macro @:pos(pos) obj = super.copyToDynamic(obj));

			{
				copyFromOther.push(macro @:pos() var obj = cast obj);
			}
		}

		function getDefExpr(f:Field, replaceNull: Bool = true) {
			return switch(f.kind) {
				case FProp(_, _, t, e), FVar(t,e):
					if (e == null) {
						if (replaceNull) {
							var typ = haxe.macro.ComplexTypeTools.toType(t);
							getDefValueForType(typ);
						}
						else {
							macro @:pos(pos) null;
						}
					} else {
						e;
					}
				default:
					Context.error("Invalid serializable field " + f.kind, f.pos);
			}
		}

		for (f in serializableFields) {
			var name = f.field.name;
			var defExpr = getDefExpr(f.field);
			var defExprNull = getDefExpr(f.field);

			copyFromDynamic.push(macro hrt.prefab.Macros.deepCopyFromDynamic(this.$name, obj.$name, $e{defExpr}));
			copyToDynamic.push(macro hrt.prefab.Macros.deepCopyToDynamic(obj.$name, this.$name, $e{defExprNull}));
		}

		for (f in copyableFields) {
			var name = f.field.name;
			var defExpr = getDefExpr(f.field);
			if (f.deepCopy) {
				copyFromOther.push(macro hrt.prefab.Macros.deepCopyFromOther(this.$name, obj.$name, null));
			} else {
				copyFromOther.push(macro this.$name = obj.$name);
			}
		}

		var cloneInitExprs = [];
		if (!isRoot) {
			cloneInitExprs.push(macro super.postCloneInit());
			for (f in cloneInitFields) {
				var name = f.name;
				var isFinal = false;
				if (f.access != null) {
					if (f.access.contains(AStatic)) {
						continue;
					}

					if (f.access.contains(AFinal)) {
						isFinal = true;
					}
				}

				switch (f.kind) {
					case FVar(_, defaultValue): {
						if (defaultValue != null) {
							if (isFinal) {
								// Force final initialisation
								cloneInitExprs.push(macro (this:Dynamic).$name = ${defaultValue});
							}
							else {
								cloneInitExprs.push(macro this.$name = ${defaultValue});
							}
						}
					}
					case FProp(_,set, _, defaultValue): {
						if (defaultValue != null) {
							switch(set) {
								case "default", "set", "null":
									cloneInitExprs.push(macro this.$name = ${defaultValue});
								case "never":
								default: Context.error("Unexpected setter kind " + set, f.pos);
							}
						}
					}
					default:

				}
			}
		}


		function makeFun(name,expr, paramType, returnType) : Field {
			return {
				name : name,
				kind : FFun({
					ret : returnType,
					expr : { expr : expr, pos : pos },
					args : paramType != null ? [{ name : "obj", type : paramType }] : [],
				}),
				meta : [{ name : ":noCompletion", pos : pos }],
				access : isRoot ? [] : [AOverride],
				pos : pos,
			};
		}

		var fields = [];
		fields.push(makeFun("copyFromDynamic", EBlock(copyFromDynamic), macro : Dynamic, null));
		var rootType =
		fields.push(makeFun("copyFromOther", EBlock(copyFromOther), Context.toComplexType(TInst(root, [])), null));

		var expr = macro {
			if (obj == null)
				obj = {};
			$b{copyToDynamic};
			return obj;
		};
		fields.push(makeFun("copyToDynamic", EBlock([expr]), macro : Dynamic, macro : Dynamic));

		fields.push(makeFun("postCloneInit", EBlock(cloneInitExprs), null, null));



		return fields;
	}

	static public function getFieldType(type: Type, field: String) : Type {
		switch(type) {
			case TDynamic(_):
				return TDynamic(null);
			case TAnonymous(a):
				return a.get().fields.find((f) -> f.name == field).type;
			case TType(a, _):
				return getFieldType(a.get().type, field);
			default:
				throw "Type does not have fields or is not supported";
		}
		return null;
	}

	static public function canBeNull(type:Type) : Bool {
		return switch (type) {
			case TDynamic(_):
				true;
			case TInst(_, _):
				true;
			case TType(a, _):
				canBeNull(a.get().type);
			case TAbstract(t,c):
				if (t.get().name == "Null")
					true;
				else
					false;
			case TAnonymous(_):
				return true;
			case TEnum(_,_):
				false;
			default:
				throw "Unhandled type " + type;
		}
	}

	// Custom allow overrides over the behavior of this function if it returns not null
	static public function deepCopyRec(type:Type, source: Expr, sourceType: Type, ?defaultValue: Expr, custom:(Type, Expr, Type, Null<Expr>) -> Null<Expr>, parentIsArray: Bool = false) : Expr {
		if (custom != null) {
			var cus = custom(type, source, sourceType, defaultValue);
			if (cus != null)
				return cus;
		}

		var nullCheck = if (canBeNull(sourceType) && !parentIsArray) {
			function(source: Expr, ?defaultValue: Expr) : Expr {
				var defVal = defaultValue != null ? switch(defaultValue.expr) {
					case EConst(CIdent("null")): null;
					default: macro $e{defaultValue};
				} : null;
				if (defVal != null)
					return macro @:pos(source.pos) $e{source} != null ? $e{source} : $e{defaultValue};
				else
					return macro @:pos(source.pos) $e{source};
			}
		} else {
			function(source: Expr, ?defaultValue: Expr) : Expr {
				return macro @:pos(source.pos) $e{source};
			}
		}

		switch (type) {
			case TAnonymous(a):
				var objFields : Array<ObjectField> = [];
				for (f in a.get().fields) {
					var name = f.name;
					var subField = macro @:pos(source.pos) ${source}.$name;
					var defVal = defaultValue != null ? switch(defaultValue.expr) {
						case EConst(CIdent("null")): null;
						default: subField;
					} : null;
					var e : Expr = deepCopyRec(f.type, subField, getFieldType(sourceType, name), defVal, custom);
					objFields.push({field : f.name, expr : e});
				}
				var declExpr : Expr = {expr: EObjectDecl(objFields), pos : source.pos};
				if (defaultValue == null) {
					defaultValue = macro null;
				}
				return macro @:pos(source.pos) {$e{source} != null ? $e{declExpr} : $e{defaultValue}};
			case TType(t, _):
				return deepCopyRec(t.get().type, source, sourceType, defaultValue, custom);
			case TInst(cl, params):
				switch(cl.toString()) {
					case "Array":
						function getArrayType(type: Type) : Type{
							//trace(type + "");
							switch (type) {
								case TDynamic(_):
									return TDynamic(null);
								case TInst(cl, params):
									if (cl.toString() == "Array")
										return params[0];
									else
										return params[0];
								case TType(a, _):
									return getArrayType(a.get().type);
								case TAbstract(a, c):
									if (a.get().name == "Null") {
										return getArrayType(c[0]);
									}
									throw 'Tying to unserialize non array ($type) into array variable ---';
								default:
									throw 'Tying to unserialize non array ($type) into array variable';
							}
						}

						var targetType = getArrayType(sourceType);

						if (defaultValue == null)
							defaultValue = macro @:pos(source.pos) [];
						return macro @:pos(source.pos) {
							if ($e{source} == null) $e{defaultValue}
							else
							{
								var _a : Array<Dynamic> = cast $e{source};
								var target = [];
								target.resize(_a.length);
								for (idx => _elem in _a) {
									target[idx] = $e{hrt.prefab.Macros.deepCopyRec(params[0], macro @:pos(source.pos) _elem, targetType, null, custom, true)};
								}
								target;
							}
						};
					case "String":
						return nullCheck(source, defaultValue); // No need to copy haxe string as they are immutable
					default:
						Context.error("Can't unserialize " + cl.toString(), source.pos);
						throw "error";
				}
			case TEnum(t, _):
				return nullCheck(source, defaultValue);
			case TAbstract(t,c):
				if (t.get().name == "Null") {
					if (defaultValue == null)
						defaultValue = macro null;
					return deepCopyRec(c[0], source, sourceType, defaultValue, custom);
				}
				else {
					var trueType = haxe.macro.TypeTools.followWithAbstracts(t.get().type, false);
					var def = defaultValue != null ? defaultValue : getDefValueForType(t.get().type);
					return nullCheck(source, defaultValue);
				}
			case TDynamic(_):
				return nullCheck(source, defaultValue);
			default:
				throw "error unhandled type " + type;
		}
	}
	#end
}