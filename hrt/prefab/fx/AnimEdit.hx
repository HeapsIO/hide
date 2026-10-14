package hrt.prefab.fx;

#if domkit

/** The animation curve of a property: a child of `owner` named after the property (`EmitterParam.animKey` for an emitter) **/
enum AnimTarget {
	ByName(owner: Prefab, name: String);
}

/**
	Animation curves edited from the inspector, Blender-like: a marker after an animatable field tells
	if it is animated (and keyed at the current time), its menu animates it, inserts or removes a key.
	An animated field shows the value at the current time of the FX, editing it sets a key there.
	The editor finds, creates and removes the animation curves here only.
**/
@:access(hrt.prefab.Prefab)
class AnimEdit {

	static var OBJECT_FIELDS = [
		"x" => "position:x", "y" => "position:y", "z" => "position:z",
		"scaleX" => "scale:x", "scaleY" => "scale:y", "scaleZ" => "scale:z",
		"rotationX" => "rotation:x", "rotationY" => "rotation:y", "rotationZ" => "rotation:z",
	];
	static var LIGHT_FIELDS = ["power", "range", "angle", "fallOff", "size"];

	/** The time of the FX `p` is in, null out of an FX **/
	public static function getTime(p: Prefab) : Null<Float> {
		if (!(p is BaseFX) && !FX.inFX(p))
			return null;
		var root = p.getRoot();
		var anim3d = Std.downcast(root.to(Object3D)?.local3d, FX.FXAnimation);
		if (anim3d != null)
			return anim3d.localTime;
		var anim2d = Std.downcast(root.to(Object2D)?.local2d, FX2D.FX2DAnimation);
		return anim2d?.localTime;
	}

	/** Loads the data of an undo step **/
	public static function tempLoad(p: Prefab, data: Dynamic) {
		#if (editor || editor_hl) p.editorTempLoad(data); #else p.load(data); #end
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

	public static function findCurve(target: AnimTarget) : Null<Curve> {
		return switch (target) {
			case ByName(owner, name):
				// a single curve can animate all the components of a vector
				Curve.getCurve(owner, name, false) ?? (name.indexOf(":") > 0 ? Curve.getCurve(owner, name.split(":")[0], false) : null);
		}
	}

	/** Binds the animatable properties of the objects, lights and shaders out of emitters of the edited prefab **/
	public static function decorate(root: hide.kit.KitRoot, prefab: Prefab) {
		if (getTime(prefab) == null || prefab.findParent(Emitter) != null || prefab.findParent(Emitter2D) != null)
			return;
		var shader = Std.downcast(prefab, Shader);
		if (shader != null) {
			var cat = root.getById("shaderCat");
			if (cat == null)
				return;
			for (c in cat.getChildren()) {
				var s = Std.downcast(c, hide.kit.Slider);
				if (s != null)
					bind(s, ByName(shader, s.id));
			}
			return;
		}
		if (prefab.to(Object3D) == null)
			return;
		var isLight = Std.isOfType(prefab, Light);
		function rec(e: hide.kit.Element) {
			for (c in e.getChildren().copy()) {
				var s = Std.downcast(c, hide.kit.Slider);
				var name = s == null ? null : OBJECT_FIELDS.get(s.id) ?? (isLight && LIGHT_FIELDS.contains(s.id) ? s.id : null);
				if (name != null)
					bind(s, ByName(prefab, name));
				else
					rec(c);
			}
		}
		rec(root);
	}

	/** Shows the animation of `target` on `slider`, nothing out of an FX **/
	public static function bind(slider: hide.kit.Slider<Float>, target: AnimTarget) {
		var owner = switch (target) { case ByName(o, _): o; };
		if (getTime(owner) == null)
			return;
		var marker = new AnimMarker(null, slider.id + "Anim", slider, target, owner);
		var parent = @:privateAccess slider.parent;
		if (!(parent is hide.kit.Line)) {
			parent = new hide.kit.Line(null, slider.id + "Line");
			@:privateAccess slider.wrapWith(parent);
		}
		var index = parent.getChildren().indexOf(slider);
		@:privateAccess parent.addChildAt(marker, index < 0 ? parent.numChildren : index + 1);
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
			tempLoad(owner, Diff.deepCopy(isUndo ? before : after));
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

	public static function animate(editor: EditContext2, target: AnimTarget, value: Float, time: Float) {
		switch (target) {
			case ByName(owner, name):
				editTree(editor, owner, () -> {
					var c = new Curve(owner, owner.shared);
					c.name = name;
					c.addKey(time, value, Linear);
				});
		}
	}

	public static function removeAnimation(editor: EditContext2, target: AnimTarget) {
		var curve = findCurve(target);
		if (curve == null)
			return;
		var owner = curve.parent;
		editTree(editor, owner, () -> curve.remove());
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
		var after = Diff.deepCopy(curve.save());
		editor.rebuildPrefab(owner);
		editor.recordUndo((isUndo) -> {
			tempLoad(curve, Diff.deepCopy(isUndo ? before : after));
			editor.rebuildPrefab(owner);
			editor.rebuildInspector();
		}, [curve]);
	}
}

/** The marker of an animatable field, after it in its line **/
@:access(hrt.prefab.Prefab)
class AnimMarker extends hide.kit.Element {
	var slider : hide.kit.Slider<Float>;
	var target : AnimTarget;
	var owner : Prefab;
	var curve : Curve;
	var lastTime : Null<Float> = null;
	/** The curve before the temporary edits of the field **/
	var pending : Dynamic;

	public function new(parent, id, slider, target, owner) {
		super(parent, id);
		this.slider = slider;
		this.target = target;
		this.owner = owner;
		curve = AnimEdit.findCurve(target);
		slider.menuItems = menu;
		if (curve == null)
			return;
		@:privateAccess slider.getFieldValue = () -> value(time());
		@:privateAccess slider.onFieldChange = (temp) -> editKey(slider.value, temp);
		slider.value = value(time());
	}

	inline function time() return AnimEdit.getTime(owner) ?? 0.;

	// a reference curve has no keys of its own
	function value(t: Float) return new Evaluator().getFloat(curve.makeVal(), t);

	function editKey(value: Float, temp: Bool) {
		pending ??= hrt.prefab.Diff.deepCopy(curve.save());
		var t = time();
		var key = AnimEdit.keyAt(curve, t);
		if (key != null)
			key.value = value;
		else
			curve.addKey(t, value);
		var editor = root.editor;
		editor.rebuildPrefab(owner);
		if (temp)
			return;
		var c = curve, owner = owner, before = pending, after = hrt.prefab.Diff.deepCopy(curve.save());
		pending = null;
		editor.recordUndo((isUndo) -> {
			AnimEdit.tempLoad(c, hrt.prefab.Diff.deepCopy(isUndo ? before : after));
			editor.rebuildPrefab(owner);
			editor.rebuildInspector();
		}, [c]);
	}

	function menu() : Array<hrt.ui.HuiMenu.MenuItem> {
		var editor = root.editor;
		var label = slider.label != null && slider.label.length > 0 ? ' (${slider.label})' : "";
		if (curve == null)
			return [{ label: "Animate" + label, click: () -> AnimEdit.animate(editor, target, slider.value, time()) }];
		var key = AnimEdit.keyAt(curve, time());
		return [
			key == null
				? { label: "Insert key" + label, click: () -> AnimEdit.setKey(editor, curve, owner, time(), slider.value) }
				: { label: "Remove key" + label, click: () -> AnimEdit.setKey(editor, curve, owner, time(), null), enabled: curve.keys.length > 1 },
			{ label: "Remove animation" + label, click: () -> AnimEdit.removeAnimation(editor, target) },
		];
	}

	function onMarkerClick() {
		var editor = root.editor;
		if (curve == null)
			AnimEdit.animate(editor, target, slider.value, time());
		else if (AnimEdit.keyAt(curve, time()) == null)
			AnimEdit.setKey(editor, curve, owner, time(), slider.value);
		else if (curve.keys.length > 1)
			AnimEdit.setKey(editor, curve, owner, time(), null);
	}

	/** Follows the time of the FX **/
	function sync() {
		var t = time();
		if (curve == null || t == lastTime || pending != null)
			return;
		lastTime = t;
		slider.value = value(t);
		native.toggleClass("key", AnimEdit.keyAt(curve, t) != null);
	}

	override function makeSelf() {
		#if js
		var e = js.Browser.document.createElement("kit-anim-marker");
		e.classList.toggle("animated", curve != null);
		e.title = curve == null ? "Animate (right click: menu)" : "Insert or remove a key at the current time (right click: menu)";
		e.addEventListener("click", (ev: js.html.MouseEvent) -> {
			ev.stopPropagation();
			if (!isDisabled())
				onMarkerClick();
		});
		e.addEventListener("contextmenu", (ev: js.html.MouseEvent) -> {
			ev.preventDefault();
			ev.stopPropagation();
			if (!isDisabled())
				hide.comp.ContextMenu.createFromEvent(ev, menu());
		});
		native = e;
		// follows the time until the inspector is rebuilt
		var shown = false;
		function loop(_) {
			if (e.isConnected) {
				shown = true;
				sync();
			} else if (shown)
				return;
			js.Browser.window.requestAnimationFrame(loop);
		}
		if (curve != null)
			js.Browser.window.requestAnimationFrame(loop);
		#else
		super.makeSelf();
		#end
	}
}

#end
