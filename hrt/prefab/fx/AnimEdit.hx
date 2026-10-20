package hrt.prefab.fx;

#if domkit

import hrt.prefab.fx.EmitterParam;

@:access(hrt.prefab.Prefab)
class AnimEdit {

	public static function getFX(p: Prefab) : { time: Float, evaluator: Evaluator } {
		if (p.findParent(Prefab, c -> c is BaseFX, true) == null)
			return null;
		var root = p.getRoot();
		var anim3d = Std.downcast(root.to(Object3D)?.local3d, FX.FXAnimation);
		if (anim3d != null)
			return { time: anim3d.localTime, evaluator: @:privateAccess anim3d.evaluator };
		var anim2d = Std.downcast(root.to(Object2D)?.local2d, FX2D.FX2DAnimation);
		return anim2d == null ? null : { time: anim2d.localTime, evaluator: @:privateAccess anim2d.evaluator };
	}

	static var CHANNELS = ["position", "rotation", "scale", "color", "visibility", "localposition", "localrotation"];

	public static function isChannel(name: String) {
		return name != null && CHANNELS.contains(name.split(":")[0].toLowerCase());
	}

	public static function isParticleCurve(curve: Curve) {
		var top : Prefab = curve;
		while (top.parent is Curve)
			top = top.parent;
		var emitter : ParamOwner = top.parent is ParamOwner ? cast top.parent : null;
		if (emitter == null)
			return top.findParent(Prefab, p -> p is ParamOwner) != null;
		return !isChannel(top.name) && !isParamName(emitter, top.name);
	}

	static function isParamName(emitter: ParamOwner, name: String) {
		var base = name?.split(":")[0];
		return Lambda.exists(emitter.getSettings(), p -> p.animate == true && p.name == base) || Lambda.exists(emitter.getModeParams(), p -> p.kind != Particle && p.name == base);
	}

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
			var span = EmitterParam.span(emitter.getMode(def.name, i), def.def[i]);
			return parts[parts.length - 1] == "min" ? span.min : span.max;
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

	public static function findCurve(owner: Prefab, name: String) : Curve {
		// a single curve can animate all the components of a vector
		return hrt.prefab.Curve.getCurve(owner, name, false) ?? (name.indexOf(":") > 0 ? hrt.prefab.Curve.getCurve(owner, name.split(":")[0], false) : null);
	}

	public static function bind(editor: EditContext2, slider: hide.kit.Slider<Float>, owner: Prefab, name: String) {
		if (getFX(owner) == null)
			return;
		var curve = findCurve(owner, name);
		function time() return getFX(owner)?.time ?? 0.;
		var label = slider.label != null && slider.label.length > 0 ? ' (${slider.label})' : "";
		function menu() : Array<hrt.ui.HuiMenu.MenuItem> {
			if (curve == null)
				return [{ label: "Animate" + label, click: () -> animate(editor, owner, name, slider.value, time()) }];
			var key = keyAt(curve, time());
			return [
				key == null
					? { label: "Insert key" + label, click: () -> setKey(editor, curve, owner, time(), slider.value) }
					: { label: "Remove key" + label, click: () -> setKey(editor, curve, owner, time(), null), enabled: curve.keys.length > 1 },
				{ label: "Remove animation" + label, click: () -> removeAnimation(editor, owner, name) },
			];
		}
		if (curve == null) {
			hide.kit.AnimMarker.addMenu(slider, menu);
			return;
		}
		var marker = new hide.kit.AnimMarker(slider, true, menu);
		marker.onMarkerClick = () -> {
			if (keyAt(curve, time()) == null)
				setKey(editor, curve, owner, time(), slider.value);
			else if (curve.keys.length > 1)
				setKey(editor, curve, owner, time(), null);
		}

		marker.isKeyed = () -> keyAt(curve, time()) != null;
		// the curve before the temporary edits of the field
		var pending : Dynamic = null;
		function value() {
			var fx = getFX(owner);
			// a reference curve has no keys of its own
			return fx == null ? slider.value : fx.evaluator.getFloat(curve.makeVal(), fx.time);
		}
		slider.getFieldValue = () -> pending != null ? slider.value : value();
		slider.onFieldChange = (temp) -> {
			pending ??= Diff.deepCopy(curve.save());
			var t = time();
			var key = keyAt(curve, t);
			if (key != null)
				key.value = slider.value;
			else
				curve.addKey(t, slider.value);
			editor.rebuildPrefab(owner);
			if (temp)
				return;
			var before = pending;
			pending = null;
			editor.recordPrefabUndo(curve, before, owner);
		}
		slider.value = value();
	}

	public static function editTree(editor: EditContext2, owner: Prefab, f: () -> Void) {
		var before = Diff.deepCopy(owner.save()), childrenBefore = owner.children.copy();
		f();
		var after = Diff.deepCopy(owner.save()), childrenAfter = owner.children.copy();
		function apply(isUndo: Bool) {
			var children = isUndo ? childrenBefore : childrenAfter;
			for (c in owner.children.copy())
				if (!children.contains(c))
					c.remove();
			for (i => c in children)
				if (c.parent != owner)
					owner.addChildAt(c, i);
			EditContext2.tempLoad(owner, Diff.deepCopy(isUndo ? before : after));
			editor.rebuildTree(owner);
			editor.rebuildPrefab(owner);
			editor.rebuildInspector();
		}
		editor.rebuildTree(owner);
		editor.rebuildPrefab(owner);
		editor.recordUndo(apply, [owner]);
	}

	public static function newCurveName(owner: Prefab, base: String) {
		var name = base, i = 1;
		while (Lambda.exists(owner.children, c -> c.name != null && c.name.toLowerCase() == name.toLowerCase()))
			name = base + (i++);
		return name;
	}

	public static function animate(editor: EditContext2, owner: Prefab, name: String, value: Float, time: Float) {
		editTree(editor, owner, () -> {
			var c = new Curve(owner, owner.shared);
			c.name = name;
			c.addKey(time, value, Linear);
		});
	}

	public static function removeAnimation(editor: EditContext2, owner: Prefab, name: String) {
		var curve = findCurve(owner, name);
		if (curve != null)
			editTree(editor, curve.parent, () -> curve.remove());
	}

	public static function keyAt(curve: Curve, time: Float) {
		return curve.findKey(time, 0.5 / 60);
	}

	/** Removes the key when `value` is null **/
	public static function setKey(editor: EditContext2, curve: Curve, owner: Prefab, time: Float, value: Null<Float>) {
		var before = Diff.deepCopy(curve.save());
		var key = keyAt(curve, time);
		if (value == null)
			curve.keys.remove(key);
		else if (key != null)
			key.value = value;
		else
			curve.addKey(time, value);
		editor.rebuildPrefab(owner);
		editor.recordPrefabUndo(curve, before, owner);
	}
}

#end
