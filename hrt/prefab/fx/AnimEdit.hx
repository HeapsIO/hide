package hrt.prefab.fx;

#if domkit

/**
	Animation curves edited from the inspector, Blender-like: a marker after an animatable field tells
	if it is animated (and keyed at the current time), its menu animates it, inserts or removes a key.
	An animated field shows the value at the current time of the FX, editing it sets a key there.
	The animation curve of a field is a child of the animated prefab, named after the property.
**/
@:access(hrt.prefab.Prefab)
class AnimEdit {

	/** The time and the evaluator of the FX `p` is in, null out of an FX **/
	public static function getFX(p: Prefab) : Null<{ time: Float, evaluator: Evaluator }> {
		if (p.findParent(Prefab, c -> c is BaseFX, true) == null)
			return null;
		var root = p.getRoot();
		var anim3d = Std.downcast(root.to(Object3D)?.local3d, FX.FXAnimation);
		if (anim3d != null)
			return { time: anim3d.localTime, evaluator: @:privateAccess anim3d.evaluator };
		var anim2d = Std.downcast(root.to(Object2D)?.local2d, FX2D.FX2DAnimation);
		return anim2d == null ? null : { time: anim2d.localTime, evaluator: @:privateAccess anim2d.evaluator };
	}

	/** Curves under emitters named after them animate the emitter object **/
	static var CHANNELS = ["position", "rotation", "scale", "color", "visibility", "localposition", "localrotation"];

	public static function isChannel(name: String) {
		return name != null && CHANNELS.contains(name.split(":")[0].toLowerCase());
	}

	/** A curve over the particle life, edited in the inspector of its emitter: under an emitter and not one of its animation curves **/
	public static function isParticleCurve(curve: Curve) {
		var top : Prefab = curve;
		while (top.parent is Curve)
			top = top.parent;
		var e = top.parent;
		if (!(e is Emitter || e is Emitter2D))
			return top.findParent(Emitter) != null || top.findParent(Emitter2D) != null;
		return !isChannel(top.name) && !isParamName(e, top.name);
	}

	/** If `name` is the name of an animation curve of an emitter param **/
	static function isParamName(emitter: Prefab, name: String) {
		var base = name?.split(":")[0];
		var is3d = emitter is Emitter;
		var settings = is3d ? Emitter.emitterParams : Emitter2D.emitterParams;
		var params = is3d ? Emitter.MODE_PARAMS : Emitter2D.MODE_PARAMS;
		return Lambda.exists(settings, p -> p.animate == true && p.name == base) || Lambda.exists(params, p -> p.kind != Particle && p.name == base);
	}

	public static function findCurve(owner: Prefab, name: String) : Null<Curve> {
		// a single curve can animate all the components of a vector
		return Curve.getCurve(owner, name, false) ?? (name.indexOf(":") > 0 ? Curve.getCurve(owner, name.split(":")[0], false) : null);
	}

	/** Shows the animation curve `name` of `owner` on `slider`, nothing out of an FX **/
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
		var marker = new hide.kit.AnimMarker(slider, curve != null, menu);
		marker.onMarkerClick = () -> {
			if (curve == null)
				animate(editor, owner, name, slider.value, time());
			else if (keyAt(curve, time()) == null)
				setKey(editor, curve, owner, time(), slider.value);
			else if (curve.keys.length > 1)
				setKey(editor, curve, owner, time(), null);
		}
		if (curve == null)
			return;

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

	/**
		Applies `f`, that changes `owner` and the curves under it, as an undo step: the data of `owner`
		and its list of children are restored on undo
	**/
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

	/** A name for a new curve under `owner` that no sibling has **/
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

	/** Sets the key at `time` to `value`, or removes it when `value` is null **/
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
