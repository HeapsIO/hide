package hrt.prefab.fx;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Emitter fields:
	- `@:s` properties, `@:range(min, max)`, `@:animate` when an animation curve can set them, `@:disp("Label", "Description")` (the description is the tooltip of its line),
	  `@:t(PFile([...]))` for a type other than the one of the field, `@:sameLine` to show it on the line of the previous property
	  (`@:line("Label")` on the first one names the line, the widgets keep their labels; else the line takes the label of the first one, the others show none);
	- `@:param(PVec(3, -10, 10), Particle, default)` params with modes (`EmitterParam`), saved under their name like the properties.
	  The Particle ones, read over the particle life, are named `partX`;
	- `@:group("Name")`: the inspector group of the field and of the next ones.
	`FIELDS` has the properties and the params in their declaration order, the one of the inspector.
	The random slots are allocated in the declaration order of the params (Emission ones have none).
	The evaluator of the emitter (`buildEvaluator`) has a `Value` of the same name for each param and animated property, built by `makeEvaluator`.
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

	// a type path from its full name, `pack.Module.Sub`
	static function typePath( name : String ) : TypePath {
		var parts = name.split(".");
		var pack = [while( parts.length > 0 && parts[0].charAt(0) == parts[0].charAt(0).toLowerCase() ) parts.shift()];
		return { pack: pack, name: parts[0], sub: parts[1] };
	}

	public static function build( evaluatorType : String ) : Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var fieldDefs = [], params = [];
		var load = [], save = [], copy = [], getCases = [], setCases = [];
		var values = [];
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
					var animate = meta(f, ":animate") != null, sameLine = meta(f, ":sameLine") != null;
					var lineMeta = meta(f, ":line"), lineLabel = lineMeta == null ? macro null : lineMeta[0];
					fieldDefs.push(macro @:pos(p) hrt.prefab.fx.EmitterParam.EmitterField.Property({ name: $v{n}, t: ${propType(f, t, init)},
						def: (${init ?? macro null} : Dynamic), groupName: $v{group}, animate: $v{animate}, sameLine: $v{sameLine}, line: $lineLabel, disp: $label, desc: $desc }));
					if( init != null && init.expr.match(EArrayDecl(_)) )
						save.push(macro @:pos(p) if( haxe.Json.stringify(this.$n) == haxe.Json.stringify($init) ) Reflect.deleteField(data, $v{n}));
					if( animate )
						values.push(macro @:pos(p) v.$n = b.animated($v{n}, hrt.prefab.fx.Evaluator.vVal(this.$n)));
				default:
				}
				continue;
			}

			var a = meta(f, ":param");
			if( a == null )
				continue;
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
			var def = macro @:pos(p) PARAMS[$v{params.length}];
			fieldDefs.push(macro @:pos(p) hrt.prefab.fx.EmitterParam.EmitterField.Param($def));
			params.push(macro @:pos(p) { name: $v{n}, t: ${a[0]}, def: ($a{defs} : Array<Float>), kind: hrt.prefab.fx.EmitterParam.ParamKind.$kind,
				groupName: $v{group}, disp: $label, desc: $desc });
			if( dim == 1 ) {
				load.push(macro @:pos(p) this.$n = hrt.prefab.fx.EmitterParam.parseMode(data.$n));
				save.push(macro @:pos(p) { var v = hrt.prefab.fx.EmitterParam.saveMode(hrt.prefab.fx.EmitterParam.saved(this, $def, 0, this.$n)); if( v != null ) data.$n = v; });
				getCases.push({ values: [macro $v{n}], expr: macro this.$n });
				setCases.push({ values: [macro $v{n}], expr: macro this.$n = m });
				copy.push(macro @:pos(p) this.$n = from.$n);
			} else {
				// the modes of the components
				f.kind = switch( f.kind ) { case FVar(t, _): FVar(t, macro [null, null, null]); default: f.kind; };
				load.push(macro @:pos(p) this.$n = hrt.prefab.fx.EmitterParam.parseVec(data.$n));
				save.push(macro @:pos(p) { var v = hrt.prefab.fx.EmitterParam.saveVec(this, $def, this.$n); if( v != null ) data.$n = v; });
				getCases.push({ values: [macro $v{n}], expr: macro this.$n[comp] });
				setCases.push({ values: [macro $v{n}], expr: macro this.$n[comp] = m });
				copy.push(macro @:pos(p) this.$n = from.$n.copy());
			}
			values.push(macro @:pos(p) v.$n = b.param($def));
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
		// each emitter object gets its own evaluator, a game can override its values
		var makeEvaluator = share ? macro return getValues().copy() : macro return buildValues();
		var valuesTP = typePath(evaluatorType), valuesCT = TPath(typePath(evaluatorType));
		var selfType = Context.toComplexType(Context.getLocalType());
		// the statics first, the ones of the class can use them
		var statics = (macro class {
			static var PARAMS : Array<hrt.prefab.fx.EmitterParam.ParamDef> = $a{params};
			public static var FIELDS : Array<hrt.prefab.fx.EmitterParam.EmitterField> = $a{fieldDefs};
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
			public function getFields() return FIELDS;
			public function getMode( name : String, comp : Int ) : hrt.prefab.fx.EmitterParam.ParamMode {
				return ${{ expr: ESwitch(macro name, getCases, macro null), pos: pos }};
			}
			public function setMode( name : String, comp : Int, m : hrt.prefab.fx.EmitterParam.ParamMode ) {
				${{ expr: ESwitch(macro name, setCases, macro throw "No param " + name), pos: pos }};
			}
			function buildValues() : $valuesCT {
				var b = new hrt.prefab.fx.EmitterParam.ParamBuilder(this);
				var v = new $valuesTP();
				$b{values};
				v.randomSlots = b.randomSlots;
				return v;
			}
			function getValues() : $valuesCT {
				$getValues;
			}
			public function makeEvaluator() : $valuesCT {
				$makeEvaluator;
			}
		}).fields;
		if( share ) {
			methods.push({ name: "sharedValues", access: [], kind: FVar(valuesCT), pos: pos });
			methods.push({ name: "valuesFrom", access: [], kind: FVar(selfType), pos: pos });
		}
		return statics.concat(fields).concat(methods);
	}

	// the evaluator of the emitter `prefabType`, with its values: the Particle params first, read at each update of each particle
	public static function buildEvaluator( prefabType : String ) : Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var prefab = switch( Context.getType(prefabType) ) {
			case TInst(c, _): c.get();
			default: Context.error(prefabType + " is not a class", pos);
		}
		var particle = [], other = [], getters = [];
		for( f in prefab.fields.get() ) {
			var n = f.name, get = "get" + n.charAt(0).toUpperCase() + n.substr(1);
			var param = f.meta.extract(":param")[0];
			if( param == null ) {
				if( f.meta.has(":s") && f.meta.has(":animate") ) {
					other.push(n);
					getters.push(macro class { public extern inline function $get( t : Float ) : Float return getFloat($i{n}, t); });
				}
				continue;
			}
			var kind = haxe.macro.ExprTools.toString(param.params[1]);
			(kind == "Particle" ? particle : other).push(n);
			// the Emission ones are read with the random of the emitter (`EmitterHelper`)
			if( kind == "Emission" )
				continue;
			// a vector: `out` is always set, false when the value is zero
			switch( param.params[0].expr ) {
			case ECall({ expr: EConst(CIdent("PVec")) }, args) if( haxe.macro.ExprTools.toString(args[0]) == "2" ):
				getters.push(macro class { public extern inline function $get( pidx : Int, t : Float, out : h2d.col.Point ) : Bool {
					getVector2(pidx, $i{n}, t, out);
					return $i{n} != hrt.prefab.fx.Value.VZero;
				}});
			case ECall({ expr: EConst(CIdent("PVec")) }, _):
				getters.push(macro class { public extern inline function $get( pidx : Int, t : Float, out : h3d.Vector4 ) : Bool {
					getFastVec(pidx, $i{n}, t, out);
					return $i{n} != hrt.prefab.fx.Value.VZero;
				}});
			default:
				getters.push(macro class { public extern inline function $get( pidx : Int, t : Float ) : Float return getFast(pidx, $i{n}, t); });
			}
		}
		var names = particle.concat(other);
		for( n in names )
			fields.push({ name: n, access: [APublic], kind: FVar(macro : hrt.prefab.fx.Value), pos: pos });
		for( g in getters )
			fields = fields.concat(g.fields);
		var cl = Context.getLocalClass().get();
		var tp : TypePath = { pack: cl.pack, name: cl.module.split(".").pop(), sub: cl.name };
		return fields.concat((macro class {
			// per particle
			public var randomSlots = 0;
			public function new() {
				super();
			}
			public function copy() {
				var v = new $tp();
				$b{[for( n in names ) macro v.$n = $i{n}]};
				v.randomSlots = randomSlots;
				return v;
			}
		}).fields);
	}
	#end
}
