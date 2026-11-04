package hrt.prefab.fx;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Emitter fields:
	- `@:s` settings, `@:range(min, max)`, `@:animate` when an animation curve can set them, `@:disp("Label", "Description")` (the description is the tooltip of its line),
	  `@:t(PFile([...]))` for a type other than the one of the field;
	- `@:param(PVec(3, -10, 10), Particle, default)` params with modes (`EmitterParam`), saved under their name like the settings;
	- `@:group("Name")`: the inspector group of the field and of the next ones.
	The inspector shows the settings and the params in their declaration order.
	The random slots are allocated in the order of `makeValues`: particle params, settings, spawn params.
**/
class EmitterMacros {

	#if macro

	static function meta( f : Field, name : String ) : Array<Expr> {
		for( m in f.meta )
			if( m.name == name )
				return m.params;
		return null;
	}

	static function propType( f : Field, t : ComplexType, init : Expr ) : Expr {
		var explicit = meta(f, ":t");
		if( explicit != null )
			return explicit[0];
		var r = meta(f, ":range") ?? [];
		var min = r[0] ?? macro null, max = r[1] ?? macro null;
		return switch( t ) {
		case TPath({ name: "Float" }): macro PFloat($min, $max);
		case TPath({ name: "Int" }): macro PInt($min, $max);
		case TPath({ name: "Bool" }): macro PBool;
		case TPath({ name: "String" }): macro PTexture;
		case TPath({ name: "Array" }):
			switch( init?.expr ) {
			case EArrayDecl(v): macro PVec($v{v.length}, $min, $max);
			default: Context.error("A vector setting needs its default", f.pos);
			}
		case TPath({ name: "GradientData" } | { sub: "GradientData" }): macro PGradient; // ??
		case TPath(p): macro PEnum($i{p.sub ?? p.name});
		default: Context.error("Unsupported setting type", f.pos);
		}
	}

	public static function build( objectType : String ) : Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var settings = [], modeParams = [], order = [];
		var load = [], save = [], copy = [], getCases = [], setCases = [];
		var particleValues = [], settingValues = [], settingApply = [], spawnValues = [], spawnApply = [];
		var group = "Params";

		for( f in fields ) {
			var g = meta(f, ":group");
			if( g != null )
				group = haxe.macro.ExprTools.getValue(g[0]);
			var p = f.pos, n = f.name;
			var disp = meta(f, ":disp") ?? [];
			var label = disp[0] ?? macro null, desc = disp[1] ?? macro null;

			if( meta(f, ":s") != null ) {
				switch( f.kind ) {
				case FVar(t, init):
					var animate = meta(f, ":animate") != null;
					order.push(n);
					settings.push(macro @:pos(p) { name: $v{n}, t: ${propType(f, t, init)}, def: (${init ?? macro null} : Dynamic), groupName: $v{group},
						animate: $v{animate}, disp: $label, desc: $desc });
					if( init != null && init.expr.match(EArrayDecl(_)) )
						save.push(macro @:pos(p) if( haxe.Json.stringify(this.$n) == haxe.Json.stringify($init) ) Reflect.deleteField(data, $v{n}));
					if( animate ) {
						settingApply.push(macro @:pos(p) obj.$n = v.settings[$v{settingValues.length}]);
						settingValues.push(macro @:pos(p) v.settings.push(b.animated($v{n}, hrt.prefab.fx.Evaluator.vVal(this.$n))));
					}
				default:
				}
				continue;
			}

			var a = meta(f, ":param");
			if( a == null )
				continue;
			order.push(n);
			var dim = switch( a[0].expr ) {
				case ECall({ expr: EConst(CIdent("PVec")) }, args): Std.parseInt(haxe.macro.ExprTools.toString(args[0]));
				default: 1;
			}
			var kind = haxe.macro.ExprTools.toString(a[1]);
			var defs = switch( a[2]?.expr ) {
				case null: [for( _ in 0...dim ) macro 0.];
				case EArrayDecl(values): values;
				default: [a[2]];
			}
			var def = macro @:pos(p) MODE_PARAMS[$v{modeParams.length}];
			modeParams.push(macro @:pos(p) { name: $v{n}, t: ${a[0]}, def: ($a{defs} : Array<Float>), kind: hrt.prefab.fx.EmitterParam.ParamKind.$kind,
				groupName: $v{group}, disp: $label, desc: $desc });
			if( dim == 1 ) {
				load.push(macro @:pos(p) this.$n = hrt.prefab.fx.EmitterParam.parseMode(data.$n));
				save.push(macro @:pos(p) { var v = hrt.prefab.fx.EmitterParam.saveMode(this.$n); if( v != null ) data.$n = v; });
				getCases.push({ values: [macro $v{n}], expr: macro this.$n });
				setCases.push({ values: [macro $v{n}], expr: macro this.$n = m });
			} else {
				load.push(macro @:pos(p) this.$n = hrt.prefab.fx.EmitterParam.parseVec(data.$n));
				save.push(macro @:pos(p) { var v = hrt.prefab.fx.EmitterParam.saveVec(this.$n); if( v != null ) data.$n = v; });
				getCases.push({ values: [macro $v{n}], expr: macro hrt.prefab.fx.EmitterParam.comp(this.$n, comp) });
				setCases.push({ values: [macro $v{n}], expr: macro this.$n = hrt.prefab.fx.EmitterParam.withComp(this.$n, comp, m) });
			}
			copy.push(macro @:pos(p) this.$n = from.$n);
			if( kind == "Spawn" ) {
				var i = spawnValues.length;
				spawnApply.push(dim == 1 ? macro @:pos(p) obj.$n = v.spawn[$v{i}][0] : macro @:pos(p) obj.$n = v.spawn[$v{i}]);
				spawnValues.push(macro @:pos(p) v.spawn.push(b.spawn($def)));
			} else
				particleValues.push(macro @:pos(p) d.$n = b.param($def));
		}

		// out of the editor the values are built once, by the source of the clones (the prefab of a loaded resource): they only depend on
		// its data, a load resets them (a resource reload); in the editor the data is edited in place, they are built at each make
		var share = !Context.defined("editor") && !Context.defined("editor_hl");
		var reset = share ? macro { sharedValues = null; valuesFrom = null; } : macro {};
		// lazy: the errors of the params come at make, as in the editor
		var copyValues = share ? macro { sharedValues = from.sharedValues; valuesFrom = from.sharedValues == null ? from : null; } : macro {};
		var getValues = share ? macro {
			if( sharedValues == null ) {
				sharedValues = valuesFrom != null ? valuesFrom.getValues() : buildValues();
				valuesFrom = null;
			}
			return sharedValues;
		} : macro return buildValues();
		var objCT = Context.toComplexType(Context.getType(objectType));
		var selfType = Context.toComplexType(Context.getLocalType());
		// the statics first, the ones of the class can use them
		var statics = (macro class {
			public static var emitterParams : Array<hrt.prefab.fx.EmitterHelper.ParamDef> = $a{settings};
			public static var MODE_PARAMS : Array<hrt.prefab.fx.EmitterParam.ModeParamDef> = $a{modeParams};
			public static var FIELDS_ORDER : Array<String> = $v{order};
		}).fields;
		var methods = (macro class {
			function loadParams( data : Dynamic ) {
				$reset;
				$b{load};
			}
			function saveParams( data : Dynamic ) {
				$b{save};
			}
			function copyParams( from : $selfType ) {
				$b{copy};
				$copyValues;
			}
			public function getParams() return emitterParams;
			public function getModeParams() return MODE_PARAMS;
			public function getFieldsOrder() return FIELDS_ORDER;
			public function getMode( name : String, comp : Int ) : hrt.prefab.fx.EmitterParam.ParamMode {
				return ${{ expr: ESwitch(macro name, getCases, macro null), pos: pos }};
			}
			public function setMode( name : String, comp : Int, m : hrt.prefab.fx.EmitterParam.ParamMode ) {
				${{ expr: ESwitch(macro name, setCases, macro throw "No param " + name), pos: pos }};
			}
			function buildValues() : hrt.prefab.fx.EmitterParam.EmitterValues {
				var b = new hrt.prefab.fx.EmitterParam.ParamBuilder(this);
				var d = new hrt.prefab.fx.Emitter.InstanceDef();
				$b{particleValues};
				var v = new hrt.prefab.fx.EmitterParam.EmitterValues(d);
				$b{settingValues};
				$b{spawnValues};
				v.randomSlots = b.randomSlots;
				return v;
			}
			public function getValues() : hrt.prefab.fx.EmitterParam.EmitterValues {
				$getValues;
			}
			public function makeValues( obj : $objCT ) : hrt.prefab.fx.EmitterParam.EmitterValues {
				var v = getValues();
				obj.instDef = v.def;
				$b{settingApply};
				$b{spawnApply};
				return v;
			}
		}).fields;
		if( share ) {
			methods.push({ name: "sharedValues", access: [], kind: FVar(macro : hrt.prefab.fx.EmitterParam.EmitterValues), pos: pos });
			methods.push({ name: "valuesFrom", access: [], kind: FVar(selfType), pos: pos });
		}
		return statics.concat(fields).concat(methods);
	}
	#end
}
