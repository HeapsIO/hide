package hrt.prefab.fx;

import hrt.prefab.Curve;
import hrt.prefab.fx.EmitterParam;

/**
	Reads the emitter params of the old format (emitters saved before `Emitter.PARAMS_VERSION`)
	into the param modes, keeping the values they evaluate to.

	Old format, per param: a base value `k` (`instScale`), a random amount `a` (`instScale_rand`,
	the value is `k + a * random(-1, 1)`), and curves found by name among the children
	(`instScale`, `instStretch:x`, `instScale:rand`, ...), first enabled match, case insensitive.
	A curve multiplies the value, or adds to it for the rotation, offset and pivot; a curve in
	RandomBlend mode replaces it by a random between its two child curves.

	The curves stay where they are and the modes reference them by path. The animation curves
	of the spawn and multiplier params (over the FX time) are left as they are: they keep
	multiplying the value (see `ModeParamDef.track`).

	The upgrade reads the raw data of the children, it runs from `load`, before they exist.
**/
class EmitterUpgrade {

	/** Called for old data the upgrade can only approximate. **/
	public static dynamic function onWarning( owner : Prefab, message : String ) {
	}

	/** New param name => old field name **/
	public static var LEGACY_NAMES = [
		"lifeTime" => "lifeTime",
		"startSpeed" => "instStartSpeed",
		"startWorldSpeed" => "instStartWorldSpeed",
		"speed" => "instSpeed",
		"worldSpeed" => "instWorldSpeed",
		"acceleration" => "instAcceleration",
		"worldAcceleration" => "instWorldAcceleration",
		"orbitSpeed" => "instOrbitSpeed",
		"orbitSpeedMultiplier" => "instOrbitSpeedOverTime",
		"maxVelocity" => "instMaxVelocity",
		"dampen" => "instDampen",
		"scale" => "instScale",
		"scaleMultiplier" => "instScaleOverTime",
		"stretch" => "instStretch",
		"stretchVelocity" => "instStretchVelocity",
		"rotation" => "instRotation",
		"pivot" => "instPivot",
		"offset" => "instOffset",
	];

	static function legacyRand( name : String ) {
		return name == "lifeTime" ? "lifeTimeRand" : name + "_rand";
	}

	/** Whether `props` holds params in the old format (an override applied over upgraded data can bring some back). **/
	public static function hasLegacyFields( props : Dynamic, defs : Array<ModeParamDef> ) {
		for( d in defs ) {
			var old = LEGACY_NAMES.get(d.name);
			if( old != d.name && Reflect.field(props, old) != null )
				return true;
			if( Reflect.field(props, legacyRand(old)) != null )
				return true;
		}
		return false;
	}

	// Raw children

	static function isCurve( data : Dynamic ) {
		var info = @:privateAccess Prefab.getPrefabInfoByName(data.type);
		return info != null && Prefab.isOfType(info.prefabClass, Curve);
	}

	/** The names the children get once loaded (curves are renamed by `Curve.load`). **/
	static function loadedNames( children : Array<Dynamic>, parentCurve : Null<String> ) : Array<String> {
		return [for( c in children ) {
			var name : String = c.name ?? "";
			isCurve(c) ? Curve.loadedName(name, parentCurve) : name;
		}];
	}

	/** Path of child `i`, unique among its siblings like `Prefab.getUniqueName`. **/
	static function uniqueName( names : Array<String>, i : Int ) {
		var n = 0;
		for( j in 0...i )
			if( names[j] == names[i] )
				n++;
		return n > 0 ? names[i] + "-" + n : names[i];
	}

	/** Mirrors `Curve.getCurve`: the first enabled curve named `name`, case insensitive. **/
	static function findCurve( children : Array<Dynamic>, names : Array<String>, name : String ) : Null<Int> {
		for( i => c in children ) {
			if( c.enabled == false || !Curve.sameName(names[i], name) || !isCurve(c) )
				continue;
			return i;
		}
		return null;
	}

	static function blendMode( c : Dynamic ) : Int {
		var b : Dynamic = c.blendMode;
		if( b == null ) return 0;
		return Std.isOfType(b, Int) ? b : Std.parseInt(b);
	}

	static function num( v : Dynamic ) : Float {
		return v == null || !(Std.isOfType(v, Float) || Std.isOfType(v, Int)) ? 0.0 : v;
	}

	/**
		Upgrades the old params of an emitter. `legacy` is set when the whole emitter is in the
		old format: params with no base or random field are upgraded from their curves alone.
		Otherwise only the params with old fields are (and replace the new ones).
		Fills `params` and returns the components that need an unused random slot before their
		own (see `Emitter.skippedRandomSlots`).
	**/
	public static function upgradeEmitter( owner : Prefab, props : Dynamic, rawChildren : Array<Dynamic>, defs : Array<ModeParamDef>,
		additive : Array<String>, legacy : Bool, params : Map<String, ParamValue> ) : Array<String> {
		var children : Array<Dynamic> = rawChildren ?? [];
		var names = loadedNames(children, null);
		var skips = [];

		for( d in defs ) {
			var old = LEGACY_NAMES.get(d.name);
			var baseField : Dynamic = old != d.name ? Reflect.field(props, old) : null;
			var randField : Dynamic = Reflect.field(props, legacyRand(old));
			if( baseField == null && randField == null && !legacy )
				continue;
			var dim = d.def.length;
			var cur = params.get(d.name);
			var out : ParamValue = [for( i in 0...dim ) cur == null ? null : cur[i]];
			var changed = false;

			for( i in 0...dim ) {
				var suffix = dim == 1 ? "" : ":" + EmitterParam.COMPONENTS[i];
				var key = dim == 1 ? d.name : d.name + "." + EmitterParam.COMPONENTS[i];
				// the old code reads the arrays as Float, a missing element is 0
				inline function comp( v : Dynamic ) : Null<Float> {
					return v == null ? null : dim == 1 ? (Std.isOfType(v, Array) ? null : num(v)) : (Std.isOfType(v, Array) ? num((v : Array<Dynamic>)[i]) : null);
				}
				var base = comp(baseField);
				// lifeTime was already a plain value, read as a constant
				if( d.name == "lifeTime" && out[i] != null )
					base = switch( out[i] ) { case MConstant(v): v; default: base; };
				var rand = comp(randField);
				var hasRand = rand != null && rand != 0;
				var k = base ?? d.def[i];

				var ci = findCurve(children, names, old + suffix);
				var ri = findCurve(children, names, old + suffix + ":rand");
				var isBlend = ci != null && blendMode(children[ci]) == 2;
				// random slots the old code took: one for the random amount, one for a RandomBlend curve
				var oldSlots = (hasRand || ri != null ? 1 : 0) + (isBlend ? 1 : 0);
				var mode : Null<ParamMode> = null;
				if( d.group != Particle ) {
					// the curves of these params are animation curves over the FX time, they are left as they are
					// (a RandomBlend one still takes its slot, see `ParamBuilder.animated`)
					if( isBlend ) oldSlots--;
					if( ri != null )
						onWarning(owner, '${old + suffix}:rand: a random curve on a ${d.group} param has no equivalent, ignored');
					if( hasRand && d.group == Spawn )
						mode = MRange(k - rand, k + rand);
					else {
						if( hasRand )
							onWarning(owner, '${d.name}: random amount $rand ignored, a multiplier is a constant');
						if( base != null || hasRand )
							mode = MConstant(k);
					}
				} else {
					var isAdditive = Lambda.exists(additive, a -> old.indexOf(a) >= 0);
					var curve = ci == null ? null : SCurve(uniqueName(names, ci));
					if( ri != null && ci == null ) {
						// the random amount follows a curve: k + a * random * curve(t)
						var a = rand ?? 1.0;
						mode = MRandomCurve(SCurve(uniqueName(names, ri)), k, k, k - a, k + a);
					} else {
						if( ri != null )
							onWarning(owner, '${old + suffix}:rand: a random curve next to a curve has no equivalent, ignored');
						if( isBlend ) {
							// lerp(curve0(t), curve1(t), random), the base and random amount are not used
							var sub : Array<Dynamic> = children[ci].children ?? [];
							var subNames = loadedNames(sub, names[ci]);
							if( sub.length < 2 || !isCurve(sub[0]) || !isCurve(sub[1]) )
								onWarning(owner, '${old + suffix}: random blend without its two child curves');
							else if( sub[0].enabled == false || sub[1].enabled == false )
								onWarning(owner, '${old + suffix}: disabled child curve of a random blend');
							inline function path( j : Int ) return SCurve(uniqueName(names, ci) + "." + (j < sub.length ? uniqueName(subNames, j) : "0"));
							mode = MCurveRange(path(0), 0, 1, path(1), 0, 1);
						} else if( curve != null ) {
							if( isAdditive )
								mode = hasRand ? MRandomCurve(curve, k - rand, k + rand, k - rand + 1, k + rand + 1) : MCurve(curve, k, k + 1);
							else
								mode = hasRand ? MRandomCurve(curve, 0, 0, k - rand, k + rand) : MCurve(curve, 0, k);
						} else if( hasRand )
							mode = MRange(k - rand, k + rand);
						else if( base != null )
							mode = MConstant(k);
					}
				}
				if( oldSlots > (EmitterParam.isRandom(mode) ? 1 : 0) )
					skips.push(key);
				if( mode != null || baseField != null || randField != null ) {
					out[i] = mode;
					changed = true;
				}
			}
			if( changed ) {
				if( EmitterParam.isUnset(out) )
					params.remove(d.name);
				else
					params.set(d.name, out);
			}
		}
		return skips.length > 0 ? skips : null;
	}

	/**
		Upgrades the curves of a shader under an emitter, evaluated over the particle life.
		The shader definition is not known at load, the kind of a param comes from its stored
		value: a float was `curve * value`, a vector came from its component curves alone,
		0 for the others (1 for w). Colors keep their curves, they are not upgraded.
	**/
	public static function upgradeShader( owner : Prefab, props : Dynamic, rawChildren : Array<Dynamic> ) : Map<String, ParamValue> {
		var children : Array<Dynamic> = rawChildren ?? [];
		var names = loadedNames(children, null);
		var out = new Map<String, ParamValue>();
		var seen = new Map();
		for( i => c in children ) {
			if( c.enabled == false || !isCurve(c) )
				continue;
			var prefix = names[i].split(":")[0];
			var low = prefix.toLowerCase();
			if( seen.exists(low) )
				continue;
			seen.set(low, true);

			// the runtime finds the curves from the shader var name, case insensitive
			var name = prefix;
			var prop : Dynamic = null;
			if( props != null )
				for( f in Reflect.fields(props) )
					if( f.toLowerCase() == low ) {
						name = f;
						prop = Reflect.field(props, f);
					}
			var group = [for( j => c in children ) if( c.enabled != false && isCurve(c) && Curve.sameName(names[j].split(":")[0], name) ) j];
			var components = Lambda.exists(group, j -> names[j].indexOf(":") >= 0);
			var isVector = Std.isOfType(prop, Array) || (prop == null && components);
			if( isVector && low.indexOf("color") >= 0 )
				continue;
			if( isVector ) {
				var dim = Std.isOfType(prop, Array) ? hxd.Math.imin((prop : Array<Dynamic>).length, 4) : 4;
				var v : ParamValue = [];
				for( k in 0...dim ) {
					var suffix = ":" + EmitterParam.COMPONENTS[k];
					var j = Lambda.find(group, j -> StringTools.endsWith(names[j].toLowerCase(), suffix));
					v.push(j != null ? MCurve(SCurve(uniqueName(names, j)), 0, 1) : MConstant(k == 3 ? 1 : 0));
				}
				out.set(name, v);
			} else {
				var j = findCurve(children, names, name);
				// component curves on a float are not read
				if( j == null )
					continue;
				// the old code multiplied by the value when it is a number, by 1 otherwise, and a missing
				// value is the default of the param: 0 for a float
				var isNumber = Std.isOfType(prop, Float) || Std.isOfType(prop, Int);
				var base = isNumber ? num(prop) : prop != null ? 1.0 : 0.0;
				if( prop == null )
					onWarning(owner, '$name: no stored value, taken as a float of default 0');
				out.set(name, [MCurve(SCurve(uniqueName(names, j)), 0, base)]);
			}
		}
		return out;
	}
}
