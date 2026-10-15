package hrt.prefab.fx;

#if domkit

import hrt.prefab.fx.EmitterParam;

enum abstract ModeKind(String) to String {
	var Constant;
	var Range;
	var Curve;
	var RandomCurve;
	var CurveRange;
}

/** Inspector of the params with modes, of the emitters and of the particle shaders **/
class EmitterEdit {

	static function kindModes(kind: ParamKind) : Array<ModeKind> {
		return switch (kind) {
			case Spawn: [Constant, Range];
			case Particle: [Constant, Range, Curve, RandomCurve, CurveRange];
			case Multiplier: [Constant];
		}
	}

	static function kindOf(m: ParamMode) : ModeKind {
		return switch (m) {
			case MConstant(_): Constant;
			case MRange(_): Range;
			case MCurve(_): Curve;
			case MRandomCurve(_): RandomCurve;
			case MCurveRange(_): CurveRange;
		}
	}

	/** `m` in `mode`, keeping its values: exactly when `mode` can express it, its middle otherwise. A new curve goes from 0 to 1 **/
	static function convert(m: Null<ParamMode>, mode: ModeKind, def: Float) : ParamMode {
		var s = null, s2 = null, f0 = def, f1 = def, t0 = def, t1 = def;
		switch (m) {
			case null:
			case MConstant(v): f0 = f1 = t0 = t1 = v;
			case MRange(min, max): f0 = t0 = min; f1 = t1 = max;
			case MCurve(sh, from, to): s = sh; f0 = f1 = from; t0 = t1 = to;
			case MRandomCurve(sh, a, b, c, d): s = sh; f0 = a; f1 = b; t0 = c; t1 = d;
			case MCurveRange(a, af, at, b, bf, bt): s = a; s2 = b; f0 = af; t0 = at; f1 = bf; t1 = bt;
		}
		if (s == null && mode != Constant && mode != Range) {
			f0 = f1 = 0;
			t0 = t1 = 1;
		}
		s ??= SEasing(Linear);
		return switch (mode) {
			case Constant: MConstant((t0 + t1) * 0.5);
			case Range: MRange(t0, t1);
			case Curve: MCurve(s, (f0 + f1) * 0.5, (t0 + t1) * 0.5);
			case RandomCurve: MRandomCurve(s, f0, f1, t0, t1);
			case CurveRange: MCurveRange(s, f0, t0, s2 ?? s, f1, t1);
		}
	}

	/** The curves under `owner` that can be a shape: not an object channel nor an animation curve **/
	static function shapeCurves(owner: Prefab) : Array<Curve> {
		return [for (c in owner.children) {
			var curve = Std.downcast(c, hrt.prefab.Curve);
			if (curve != null && AnimEdit.isParticleCurve(curve))
				curve;
		}];
	}

	static function shapeFunction(owner: Prefab, s: ParamShape) : Float -> Float {
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

	/** The easings offered by the shape select: Quart and Quint are left out, they stay shown where they are used **/
	static var EASINGS = Easing.ALL.filter(e -> { var s : String = e; s.indexOf("Quart") < 0 && s.indexOf("Quint") < 0; });

	/** A thumbnail of `e`, as an inline svg: the same vertical scale for all, to fit the overshoot of Back and Elastic **/
	static function easingThumbnail(e: Easing) : String {
		final W = 36, H = 24, PAD = 3, LO = -0.4, HI = 1.4, N = 40;
		inline function fmt(v: Float) return Math.round(v * 10) / 10;
		function y(v: Float) return fmt(H - PAD - (v - LO) / (HI - LO) * (H - PAD * 2));
		var points = [for (i in 0...N + 1) fmt(PAD + i / N * (W - PAD * 2)) + "," + y(e.eval(i / N))].join(" ");
		return '<svg width="$W" height="$H" style="vertical-align: middle; margin: 1px 8px 1px 0; background: #161616; border-radius: 2px">'
			+ '<line x1="0" x2="$W" y1="${y(0)}" y2="${y(0)}" stroke="#444"/><line x1="0" x2="$W" y1="${y(1)}" y2="${y(1)}" stroke="#444"/>'
			+ '<polyline points="$points" fill="none" stroke="#f05a5a" stroke-width="1.5"/></svg>';
	}

	/** A select of the shapes: a new curve (named after `name`), the curves under `owner`, the easings **/
	static function shapeSelect(ctx: EditContext2, parent: hide.kit.Element, id: String, owner: Prefab, s: ParamShape, name: String, set: ParamShape -> Void) {
		var select = new hide.kit.Select(parent, id);
		var curves : Array<hide.kit.Select.SelectEntry> = [for (c in shapeCurves(owner)) {
			var path = EmitterParam.curvePath(owner, c);
			{ value: "curve:" + path, label: path };
		}];
		var current = switch (s) { case SCurve(path): "curve:" + path; case SEasing(e): "ease:" + e; };
		if (!Lambda.exists(curves, e -> e.value == current) && s.match(SCurve(_)))
			curves.push({ value: current, label: current.substr(6) + " (missing)" });
		var easings = EASINGS.copy();
		switch (s) {
			case SEasing(e) if (!easings.contains(e)): easings.push(e);
			default:
		}
		select.setEntries([
			{ value: "new", label: "New curve" },
			{ value: null, label: "Reference", children: curves },
			{ value: null, label: "Easing", children: [for (e in easings) { value: "ease:" + e, label: hide.kit.Macros.camelToSpaceCase(e), preview: easingThumbnail(e) }] },
		]);
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
		The lines of param `def` of `owner` in `parent`, one mode per component among `modes`. An unset component
		shows its default value grayed out: editing it sets it, and a constant set back to its default is unset.
		`set` stores a new value, `onChange` follows each edit. The Spawn and Multiplier fields can be animated (`AnimEdit`).
	**/
	public static function param(ctx: EditContext2, parent: hide.kit.Element, owner: Prefab, def: ModeParamDef, modes: Array<ModeKind>,
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
			// no difference between the default value and no value
			if (m != null && m.match(MConstant(_)) && Type.enumParameters(m)[0] == def.def[i])
				m = null;
			var v = get()?.copy() ?? [for (_ in 0...dim) null];
			v[i] = m;
			set(Lambda.exists(v, m -> m != null) ? v : null);
		}

		var value = get() ?? [for (_ in 0...dim) null];
		var compName = (i: Int) -> EmitterParam.COMPONENTS[i].toUpperCase();

		/** Changes the param from a menu: an undo step of the inspector **/
		function menuEdit(line: hide.kit.Element, f: () -> Void) {
			@:privateAccess line.change({ callback: f, isTemporaryEdit: false, recordUndo: true });
			rebuild();
		}
		/** The context menu of component `i`: its mode (an unset one shows a constant), removing it, removing the param **/
		function compItems(line: hide.kit.Element, i: Int) : Array<hrt.ui.HuiMenu.MenuItem> {
			var cur = get();
			var m = cur == null ? null : cur[i];
			var kind = m == null ? Constant : kindOf(m);
			// a constant at its default is shown unset: nothing to remove
			function isSet(j: Int) {
				var c = cur == null ? null : cur[j];
				return c != null && !(c.match(MConstant(_)) && Type.enumParameters(c)[0] == def.def[j]);
			}
			var items : Array<hrt.ui.HuiMenu.MenuItem> = [];
			if (dim > 1)
				items.push({ isSeparator: true, label: label + " " + compName(i) });
			if (modes.length > 1) {
				for (mode in modes)
					items.push({ label: hide.kit.Macros.camelToSpaceCase(mode), radio: () -> kind == mode,
						click: () -> menuEdit(line, () -> setComp(i, convert(m, mode, def.def[i]))) });
				items.push({ isSeparator: true });
			}
			items.push({ label: dim == 1 ? "Remove" : "Remove " + compName(i), click: () -> menuEdit(line, () -> setComp(i, null)), enabled: isSet(i) });
			if (dim > 1)
				items.push({ label: "Remove all", click: () -> menuEdit(line, () -> set(null)), enabled: Lambda.exists([for (j in 0...dim) j], isSet) });
			return items;
		}

		// constant components on one line
		var compact = dim > 1 && Lambda.foreach(value, m -> m == null || m.match(MConstant(_)));
		var compactLine = null;
		if (compact) {
			compactLine = new hide.kit.Line(parent, def.name);
			compactLine.label = label;
		}
		for (i in 0...dim) {
			var comp = EmitterParam.COMPONENTS[i];
			var id = def.name + (dim == 1 ? "" : comp.toUpperCase());
			var suffix = compact ? comp.toUpperCase() : "";
			var line = compactLine;
			// the elements that have the menu of the component: its value on the line of the vector, its lines otherwise
			var menuOwners : Array<hide.kit.Element> = [];
			if (line == null) {
				line = new hide.kit.Line(parent, id);
				line.label = dim == 1 ? label : label + " " + comp.toUpperCase();
				// the labels of the fields stay with them (Min, Max)
				line.stealLabel = false;
				menuOwners.push(line);
			}
			var m = value[i];

			// the fields of the mode are the variables bound by the switch below, `make` builds the mode from them
			var make : () -> ParamMode = null;
			function apply() setComp(i, make());
			function animKey(?field: String) return def.kind == Particle ? null : EmitterParam.animKey(def, i, field);
			function slider(parent: hide.kit.Element, sid: String, label: String, value: Float, defaultValue: Float, set: Float -> Void, ?anim: String, ?changed: () -> Void) {
				var s = new hide.kit.Slider<Float>(parent, sid);
				if (compact)
					menuOwners.push(s);
				s.label = label;
				s.value = value;
				s.min = range.min;
				s.max = range.max;
				s.defaultValue = defaultValue;
				s.showRange = range.min != null && range.max != null;
				s.onFieldChange = (_) -> {
					set(s.value);
					apply();
					// a constant at its default is unset: grayed out
					if (make().match(MConstant(_)))
						s.faded = s.value == def.def[i];
				}
				s.onValueChange = (temp) -> {
					onChange(temp);
					if (changed != null) changed();
					// set or unset by the edit: its menu changes
					var now = get();
					if (!temp && (now != null && now[i] != null) != (m != null))
						ctx.rebuildInspector();
				}
				s.anim = anim;
				return s;
			}

			// a curve editor, the `to` fields on top and the `from` ones below
			/**
				A curve editor, and below it on one line the `from` fields (the start of the particle life, at
				the left) and the `to` ones (its end, at the right), with a button swapping them
			**/
			function curve(s: ParamShape, from: Array<{ v: () -> Float, set: Float -> Void }>, to: Array<{ v: () -> Float, set: Float -> Void }>, ranges: () -> Array<hide.kit.ParamCurve.ParamRange>, suffix: String) {
				var graph = new hide.kit.ParamCurve(parent, id + "Curve" + suffix, owner, shapeFunction(owner, s), ranges(), editableCurve(owner, s));
				var bounds = new hide.kit.Line(parent, id + "Bounds" + suffix);
				bounds.cssClass = "kit-param-bounds";
				bounds.stealLabel = false;
				menuOwners.push(bounds);
				// the view follows the range
				function changed() {
					graph.setRanges(ranges());
				}
				var names = to.length == 1 ? [""] : [" min", " max"];
				for (j => f in from)
					slider(bounds, "from" + j, "", f.v(), 0, f.set, null, changed).tooltip = "From" + names[j] + ": at the birth of the particle";
				var swap = new hide.kit.Button(bounds, "swap", "⇄");
				swap.tooltip = "Swap from and to";
				swap.onClick = () -> {
					for (j in 0...from.length) {
						var v = from[j].v();
						from[j].set(to[j].v());
						to[j].set(v);
					}
					apply();
					rebuild();
				}
				for (j => f in to)
					slider(bounds, "to" + j, "", f.v(), 1, f.set, null, changed).tooltip = "To" + names[j] + ": at the death of the particle";
			}
			function shape(parent: hide.kit.Element, sid: String, s: ParamShape, set: ParamShape -> Void) {
				shapeSelect(ctx, parent, sid, owner, s, def.name + (dim == 1 ? "" : comp.toUpperCase()), (s) -> {
					set(s);
					apply();
				});
			}
			inline function mid(a: Float, b: Float) return (a + b) * 0.5;

			switch (m) {
				case null:
					var v = def.def[i];
					make = () -> MConstant(v);
					slider(line, "value" + suffix, compact ? compName(i) : "", v, v, x -> v = x, animKey()).faded = true;
				case MConstant(v):
					make = () -> MConstant(v);
					slider(line, "value" + suffix, compact ? compName(i) : "", v, def.def[i], x -> v = x, animKey()).faded = v == def.def[i];
				case MRange(min, max):
					make = () -> MRange(min, max);
					slider(line, "min", "Min", min, def.def[i], x -> min = x, animKey("min"));
					slider(line, "max", "Max", max, def.def[i], x -> max = x, animKey("max"));
				case MCurve(s, from, to):
					make = () -> MCurve(s, from, to);
					shape(line, "shape0", s, x -> s = x);
					curve(s, [{ v: () -> from, set: x -> from = x }], [{ v: () -> to, set: x -> to = x }], () -> [{ from: from, to: to }], "");
				case MRandomCurve(s, fromMin, fromMax, toMin, toMax):
					make = () -> MRandomCurve(s, fromMin, fromMax, toMin, toMax);
					shape(line, "shape0", s, x -> s = x);
					curve(s, [{ v: () -> fromMin, set: x -> fromMin = x }, { v: () -> fromMax, set: x -> fromMax = x }], [{ v: () -> toMin, set: x -> toMin = x }, { v: () -> toMax, set: x -> toMax = x }],
						() -> [{ from: mid(fromMin, fromMax), to: mid(toMin, toMax) }, { from: fromMin, to: toMin }, { from: fromMax, to: toMax }], "");
				case MCurveRange(a, aFrom, aTo, b, bFrom, bTo):
					make = () -> MCurveRange(a, aFrom, aTo, b, bFrom, bTo);
					var lineA = new hide.kit.Line(parent, id + "Shape0");
					lineA.label = "A";
					menuOwners.push(lineA);
					shape(lineA, "shape0", a, x -> a = x);
					curve(a, [{ v: () -> aFrom, set: x -> aFrom = x }], [{ v: () -> aTo, set: x -> aTo = x }], () -> [{ from: aFrom, to: aTo }], "0");
					var lineB = new hide.kit.Line(parent, id + "Shape1");
					lineB.label = "B";
					menuOwners.push(lineB);
					shape(lineB, "shape3", b, x -> b = x);
					curve(b, [{ v: () -> bFrom, set: x -> bFrom = x }], [{ v: () -> bTo, set: x -> bTo = x }], () -> [{ from: bFrom, to: bTo }], "1");
			}
			var menuLine = line;
			for (o in menuOwners)
				o.menuItems = () -> compItems(menuLine, i);
		}
	}

	/**
		The inspector of an emitter: its `settings` (the `@:animate` ones can be animated) and its params
		with modes, grouped in categories. A change of a `refresh` setting rebuilds the inspector,
		`onChange(name)` follows each edit.
	**/
	public static function edit(ctx: EditContext2, owner: ParamOwner, settings: Array<EmitterHelper.ParamDef>, refresh: Array<String>, ?onChange: String -> Void) {
		var emitter : Prefab = cast owner;
		function changed(name: String, temp: Bool) {
			if (name == "useRandomGradient")
				Reflect.setField(emitter, "randomGradient", Reflect.field(emitter, name) ? hrt.impl.Gradient.getDefaultGradientData() : null);
			if (onChange != null)
				onChange(name);
			ctx.rebuildPrefab(emitter);
			if (!temp && refresh.contains(name))
				ctx.rebuildInspector();
		}
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
						s.onValueChange = (temp) -> changed(p.name, temp);
					}
				default:
					var widget = cat.buildProp(p, emitter);
					if (widget == null)
						continue;
					widget.onValueChange = (temp) -> changed(p.name, temp);
					var slider = Std.downcast(widget, hide.kit.Slider);
					if (p.animate && slider != null)
						slider.anim = p.name;
			}
		}

		for (p in owner.getModeParams())
			param(ctx, getCategory(p.groupName), emitter, p, kindModes(p.kind), () -> owner.getParam(p.name), (v) -> owner.setParam(p.name, v), (temp) -> changed(p.name, temp));
	}
}

#end
