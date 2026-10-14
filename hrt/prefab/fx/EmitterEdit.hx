package hrt.prefab.fx;

#if domkit

import hrt.prefab.fx.EmitterParam;

/**
	Inspector of the params with modes, of the emitters and of the particle shaders (see emitter-spec.md, UI).
**/
class EmitterEdit {

	public static var MODES = ["Constant", "Range", "Curve", "RandomCurve", "CurveRange"];
	static var MODE_LABELS = ["Constant", "Range", "Curve", "Random Curve", "Curve Range"];

	public static function kindModes(kind: ParamKind) : Array<String> {
		return switch (kind) {
			case Spawn: ["Constant", "Range"];
			case Particle: MODES;
			case Multiplier: ["Constant"];
		}
	}

	/** `m` in `mode`, keeping its values: exactly when `mode` can express it, its middle otherwise **/
	public static function convert(m: Null<ParamMode>, mode: String, def: Float) : ParamMode {
		var s = null, s2 = null, f0 = def, f1 = def, t0 = def, t1 = def;
		switch (m) {
			case null:
			case MConstant(v): f0 = f1 = t0 = t1 = v;
			case MRange(min, max): f0 = t0 = min; f1 = t1 = max;
			case MCurve(sh, from, to): s = sh; f0 = f1 = from; t0 = t1 = to;
			case MRandomCurve(sh, a, b, c, d): s = sh; f0 = a; f1 = b; t0 = c; t1 = d;
			case MCurveRange(a, af, at, b, bf, bt): s = a; s2 = b; f0 = af; t0 = at; f1 = bf; t1 = bt;
		}
		s ??= SEasing(Linear);
		return switch (mode) {
			case "Range": MRange(t0, t1);
			case "Curve": MCurve(s, (f0 + f1) * 0.5, (t0 + t1) * 0.5);
			case "RandomCurve": MRandomCurve(s, f0, f1, t0, t1);
			case "CurveRange": MCurveRange(s, f0, t0, s2 ?? s, f1, t1);
			default: MConstant((t0 + t1) * 0.5);
		}
	}

	/** The curves under `owner` that can be a shape: not an object channel nor an animation curve **/
	static function shapeCurves(owner: Prefab) : Array<Curve> {
		return [for (c in owner.children) {
			var curve = Std.downcast(c, Curve);
			if (curve != null && AnimEdit.isParticleCurve(curve))
				curve;
		}];
	}

	public static function shapeFunction(owner: Prefab, s: ParamShape) : Float -> Float {
		var v = ParamBuilder.shape(owner, s);
		var ev = AnimEdit.getFX(owner)?.evaluator ?? new Evaluator();
		return (t) -> ev.getFloat(v, t);
	}

	/** The curve of `s` when its keys can be edited **/
	static function editableCurve(owner: Prefab, s: ParamShape) : Null<Curve> {
		return switch (s) {
			case SCurve(path):
				var c = EmitterParam.resolveCurve(owner, path);
				c != null && c.blendMode == None ? c : null;
			case SEasing(_): null;
		}
	}

	/** A select of the shapes: the curves under `owner`, a new one (named after `name`), the easings **/
	static function shapeSelect(ctx: EditContext2, parent: hide.kit.Element, id: String, owner: Prefab, s: ParamShape, name: String, set: ParamShape -> Void) {
		var select = new hide.kit.Select(parent, id);
		var entries : Array<hide.kit.Select.SelectEntry> = [for (c in shapeCurves(owner)) {
			var path = EmitterParam.curvePath(owner, c);
			{ value: "curve:" + path, label: path };
		}];
		var current = switch (s) { case SCurve(path): "curve:" + path; case SEasing(e): "ease:" + e; };
		if (!Lambda.exists(entries, e -> e.value == current) && s.match(SCurve(_)))
			entries.push({ value: current, label: current.substr(6) + " (missing)" });
		entries.push({ value: "new", label: "New curve" });
		for (e in Easing.ALL)
			entries.push({ value: "ease:" + e, label: hide.kit.Macros.camelToSpaceCase(e) });
		select.setEntries(entries);
		select.value = current;
		select.defaultValue = current;
		select.onValueChange = (_) -> {
			var v : String = select.value;
			if (v == "new") {
				AnimEdit.editTree(ctx, owner, () -> {
					var c = new Curve(owner, owner.shared);
					c.name = AnimEdit.newCurveName(owner, name + "Curve");
					c.addKey(0, 0, Linear);
					c.addKey(1, 1, Linear);
					set(SCurve(EmitterParam.curvePath(owner, c)));
				});
			} else
				set(StringTools.startsWith(v, "curve:") ? SCurve(v.substr(6)) : SEasing(v.substr(5)));
			ctx.rebuildPrefab(owner);
			ctx.rebuildInspector();
		}
	}

	/**
		The lines of param `def` of `owner` in `parent`, one mode per component among `modes`, unset showing
		a `+`. `set` stores a new value, `onChange` follows each edit. The Spawn and Multiplier fields can be
		animated (`AnimEdit`).
	**/
	public static function param(ctx: EditContext2, parent: hide.kit.Element, owner: Prefab, def: ModeParamDef, modes: Array<String>,
			get: () -> Null<ParamValue>, set: Null<ParamValue> -> Void, onChange: Bool -> Void) {
		var dim = def.def.length;
		var label = def.disp ?? hide.kit.Macros.camelToSpaceCase(def.name);
		var range = switch (def.t) {
			case PFloat(min, max), PVec(_, min, max): { min: min, max: max };
			default: { min: null, max: null };
		}
		function rebuild() {
			onChange(false);
			ctx.rebuildInspector();
		}
		function setComp(i: Int, m: Null<ParamMode>) {
			var v = get()?.copy() ?? [for (_ in 0...dim) null];
			v[i] = m;
			set(Lambda.exists(v, m -> m != null) ? v : null);
		}

		var value = get();
		if (value == null) {
			var line = new hide.kit.Line(parent, def.name);
			line.label = label;
			var add = new hide.kit.Button(line, "add", "+");
			add.tooltip = "Set (default " + def.def.join(", ") + ")";
			add.onClick = () -> {
				set([for (d in def.def) MConstant(d)]);
				rebuild();
			}
			return;
		}

		for (i in 0...dim) {
			var comp = EmitterParam.COMPONENTS[i];
			var id = def.name + (dim == 1 ? "" : comp.toUpperCase());
			var line = new hide.kit.Line(parent, id);
			line.label = dim == 1 ? label : label + " " + comp.toUpperCase();
			var m = value[i];
			if (m == null) {
				var add = new hide.kit.Button(line, "add", "+");
				add.onClick = () -> {
					setComp(i, MConstant(def.def[i]));
					rebuild();
				}
				continue;
			}

			var select = new hide.kit.Select(line, "mode");
			var entries : Array<hide.kit.Select.SelectEntry> = [for (mode in modes) { value: mode, label: MODE_LABELS[MODES.indexOf(mode)] }];
			entries.push({ value: "unset", label: "Unset" });
			select.setEntries(entries);
			var mode = Type.enumConstructor(m).substr(1);
			select.value = mode;
			select.defaultValue = mode;
			select.onValueChange = (_) -> {
				setComp(i, select.value == "unset" ? null : convert(get()[i], select.value, def.def[i]));
				rebuild();
			}

			// the fields of the mode, by their index in the constructor
			var p = Type.enumParameters(m);
			function apply() setComp(i, Type.createEnum(ParamMode, Type.enumConstructor(m), p));
			function animKey(?field: String) return def.kind == Particle ? null : EmitterParam.animKey(def, i, field);
			function slider(parent: hide.kit.Element, sid: String, label: String, k: Int, ?anim: String, ?changed: () -> Void) {
				var s = new hide.kit.Slider<Float>(parent, sid);
				s.label = label;
				s.value = p[k];
				s.min = range.min;
				s.max = range.max;
				s.defaultValue = def.def[i];
				s.showRange = range.min != null && range.max != null;
				s.onFieldChange = (_) -> {
					p[k] = s.value;
					apply();
				}
				s.onValueChange = (temp) -> {
					onChange(temp);
					if (changed != null) changed();
				}
				s.anim = anim;
			}

			// a curve editor, the `to` fields on top and the `from` ones below
			function curve(sk: Int, from: Array<Int>, to: Array<Int>, ranges: () -> Array<hide.kit.ParamCurve.ParamRange>, suffix: String) {
				var s : ParamShape = p[sk];
				var top = new hide.kit.Line(parent, id + "To" + suffix);
				top.label = "To";
				var graph = new hide.kit.ParamCurve(parent, id + "Curve" + suffix, owner, shapeFunction(owner, s), ranges(), editableCurve(owner, s));
				var bottom = new hide.kit.Line(parent, id + "From" + suffix);
				bottom.label = "From";
				function changed() {
					graph.ranges = ranges();
					graph.refresh();
				}
				var names = to.length == 1 ? [""] : ["Min", "Max"];
				for (j => k in to)
					slider(top, "to" + j, names[j], k, null, changed);
				for (j => k in from)
					slider(bottom, "from" + j, names[j], k, null, changed);
			}
			function shape(parent: hide.kit.Element, sk: Int) {
				shapeSelect(ctx, parent, "shape" + sk, owner, p[sk], def.name + (dim == 1 ? "" : comp.toUpperCase()), (s) -> {
					p[sk] = s;
					apply();
				});
			}
			inline function mid(a: Float, b: Float) return (a + b) * 0.5;

			switch (m) {
				case MConstant(_):
					slider(line, "value", "", 0, animKey());
				case MRange(_):
					slider(line, "min", "Min", 0, animKey("min"));
					slider(line, "max", "Max", 1, animKey("max"));
				case MCurve(_):
					shape(line, 0);
					curve(0, [1], [2], () -> [{ from: p[1], to: p[2] }], "");
				case MRandomCurve(_):
					shape(line, 0);
					curve(0, [1, 2], [3, 4], () -> [{ from: mid(p[1], p[2]), to: mid(p[3], p[4]) }, { from: p[1], to: p[3] }, { from: p[2], to: p[4] }], "");
				case MCurveRange(_):
					for (j => sk in [0, 3]) {
						var sub = new hide.kit.Line(parent, id + "Shape" + j);
						sub.label = j == 0 ? "A" : "B";
						shape(sub, sk);
						curve(sk, [sk + 1], [sk + 2], () -> [{ from: p[sk + 1], to: p[sk + 2] }], "" + j);
					}
			}
		}
	}

	/**
		The inspector of an emitter: its `settings` (the `@:animate` ones can be animated) and its params
		with modes, grouped in categories. `onChange(name, temp)` follows each edit.
	**/
	public static function edit(ctx: EditContext2, emitter: Prefab, settings: Array<EmitterHelper.ParamDef>, params: Array<ModeParamDef>,
			getParam: String -> Null<ParamValue>, setParam: (String, Null<ParamValue>) -> Void, onChange: (String, Bool) -> Void) {
		var categories = new Map<String, hide.kit.Category>();
		function getCategory(name: String) {
			var cat = categories.get(name);
			if (cat == null) {
				cat = new hide.kit.Category(ctx.root, name, name);
				categories.set(name, cat);
			}
			return cat;
		}

		for (p in settings) {
			var cat = getCategory(p.groupName ?? "Emitter");
			switch (p.t) {
				case PVec(n, min, max) if (p.name.toLowerCase().indexOf("color") < 0):
					var line = new hide.kit.Line(cat, p.name);
					line.label = p.disp ?? hide.kit.Macros.camelToSpaceCase(p.name);
					var vec : Array<Float> = Reflect.field(emitter, p.name);
					for (i in 0...n) {
						var s = new hide.kit.Slider<Float>(line, p.name + i);
						s.label = ["X", "Y", "Z", "W"][i];
						s.value = vec[i];
						s.min = min;
						s.max = max;
						s.showRange = min != null && max != null;
						s.onFieldChange = (_) -> vec[i] = s.value;
						s.onValueChange = (temp) -> onChange(p.name, temp);
					}
				default:
					var widget = cat.buildProp(p, emitter);
					if (widget == null)
						continue;
					widget.onValueChange = (temp) -> onChange(p.name, temp);
					var slider = Std.downcast(widget, hide.kit.Slider);
					if (p.animate && slider != null)
						slider.anim = p.name;
			}
		}

		for (p in params)
			param(ctx, getCategory(p.groupName), emitter, p, kindModes(p.kind), () -> getParam(p.name), (v) -> setParam(p.name, v), (temp) -> onChange(p.name, temp));
	}
}

#end
