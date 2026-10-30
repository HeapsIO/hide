package hrt.prefab.fx;

#if domkit

import hrt.prefab.fx.EmitterParam;

@:access(hrt.prefab.Prefab)
class AnimEdit {

	public static function animKeys(owner: Prefab, prop: String) : Array<String> {
		var emitter : ParamOwner = owner is ParamOwner ? cast owner : null;
		if (emitter == null)
			return null;
		var parts = prop.split(":");
		var def = Lambda.find(emitter.getModeParams(), p -> p.name == parts[0]);
		if (def == null)
			return Lambda.exists(emitter.getSettings(), p -> p.animate == true && p.name == prop) ? [prop] : null;
		var i = parts.length > 1 ? EmitterParam.COMPONENTS.indexOf(parts[1]) : 0;
		if (def.kind == Particle || i < 0)
			return null;
		return switch (emitter.getMode(def.name, i)) {
			case Range(_): [EmitterParam.animKey(def, i, "min"), EmitterParam.animKey(def, i, "max")];
			case null, _: [EmitterParam.animKey(def, i)];
		}
	}

	public static function currentValue(owner: Prefab, key: String) : Null<Float> {
		inline function num(v: Dynamic) : Null<Float> return Std.isOfType(v, Float) || Std.isOfType(v, Int) ? (v : Float) : null;
		var parts = key.split(":");
		var emitter : ParamOwner = owner is ParamOwner ? cast owner : null;
		var def = emitter == null ? null : Lambda.find(emitter.getModeParams(), p -> p.name == parts[0]);
		if (def != null) {
			var i = parts.length > 1 ? hxd.Math.imax(0, EmitterParam.COMPONENTS.indexOf(parts[1])) : 0;
			var bounds = span(emitter.getMode(def.name, i), def.def[i]);
			return parts[parts.length - 1] == "min" ? bounds.min : bounds.max;
		}
		var comp = parts.length > 1 ? parts[1] : "x";
		if (owner is Object3D || owner is Object2D) {
			switch (parts[0]) {
				case "position": return num(Reflect.field(owner, comp));
				case "rotation" if (owner is Object2D): return (cast owner : Object2D).rotation;
				case "rotation", "scale": return num(Reflect.field(owner, parts[0] + comp.toUpperCase()));
				case "localPosition", "localRotation": return 0.;
				default:
			}
		}
		if (owner is Shader || owner is hrt.prefab.rfx.ScreenShaderGraph) {
			var prop : Dynamic = owner.props == null ? null : Reflect.field(owner.props, parts[0]);
			if (Std.isOfType(prop, Array) && parts.length > 1)
				prop = (prop : Array<Dynamic>)[EmitterParam.COMPONENTS.indexOf(parts[1])];
			return num(prop);
		}
		if (emitter != null || owner is hrt.prefab.rfx.RendererFX || (owner is Light && parts.length == 1))
			return num(Reflect.field(owner, key));
		return null;
	}

	static function span(m: ParamMode, def: Float) : { min: Float, max: Float } {
		return switch (m) {
			case Range(min, max): { min: min, max: max };
			case Constant(v): { min: v, max: v };
			case null, _: { min: def, max: def };
		}
	}
}

#end
