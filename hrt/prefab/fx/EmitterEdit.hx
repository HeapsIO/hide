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
			case Constant(_): Constant;
			case Range(_): Range;
			case Curve(_): Curve;
			case RandomCurve(_): RandomCurve;
			case CurveRange(_): CurveRange;
		}
	}

	/** `m` in `mode`, keeping its values: exactly when `mode` can express it, its middle otherwise. A new curve (`newCurve`) goes from 0 to 1 **/
	static function convert(m: ParamMode, mode: ModeKind, def: Float, newCurve: () -> String) : ParamMode {
		var s = null, s2 = null, f0 = def, f1 = def, t0 = def, t1 = def;
		switch (m) {
			case null:
			case Constant(v): f0 = f1 = t0 = t1 = v;
			case Range(min, max): f0 = t0 = min; f1 = t1 = max;
			case Curve(sh, from, to): s = sh; f0 = f1 = from; t0 = t1 = to;
			case RandomCurve(sh, a, b, c, d): s = sh; f0 = a; f1 = b; t0 = c; t1 = d;
			case CurveRange(a, af, at, b, bf, bt): s = a; s2 = b; f0 = af; t0 = at; f1 = bf; t1 = bt;
		}
		if (s == null && mode != Constant && mode != Range) {
			f0 = f1 = 0;
			t0 = t1 = 1;
			s = newCurve();
		}
		return switch (mode) {
			case Constant: Constant((t0 + t1) * 0.5);
			case Range: Range(t0, t1);
			case Curve: Curve(s, (f0 + f1) * 0.5, (t0 + t1) * 0.5);
			case RandomCurve: RandomCurve(s, f0, f1, t0, t1);
			case CurveRange: CurveRange(s, f0, t0, s2 ?? s, f1, t1);
		}
	}

	/** The curves under `owner` a param can use: not an object channel nor an animation curve **/
	static function paramCurves(owner: Prefab) : Array<Curve> {
		return [for (c in owner.children) {
			var curve = Std.downcast(c, hrt.prefab.Curve);
			if (curve != null && AnimEdit.isParticleCurve(curve))
				curve;
		}];
	}

	static function curveFunction(owner: Prefab, s: String) : Float -> Float {
		var v = ParamBuilder.curveValue(owner, s);
		var ev = AnimEdit.getFX(owner)?.evaluator ?? new Evaluator();
		return (t) -> ev.getFloat(v, t);
	}

	/** The two curves of a blend, from 0 to 1, shown under it **/
	static function blendFunctions(owner: Prefab, s: String) : Array<Float -> Float> {
		return switch (ParamBuilder.curveValue(owner, s)) {
			case VParamCurve(c, from, to) if (c.blendMode == Blend):
				[for (i in 0...2) { var b : Curve = cast c.children[i]; (t) -> hxd.Math.lerp(from, to, b.getVal(t)); }];
			default: [];
		}
	}

	static function editableCurve(owner: Prefab, path: String) : Curve {
		var c = EmitterParam.resolveCurve(owner, path);
		return c != null && c.blendMode == None ? c : null;
	}

	/** A new linear curve from 0 to 1 under `owner`, named after `name`: its path **/
	static function newCurve(owner: Prefab, name: String) : String {
		var c = new Curve(owner, owner.shared);
		c.name = AnimEdit.newCurveName(owner, name + "Curve");
		c.addKey(0, 0, Linear);
		c.addKey(1, 1, Linear);
		return EmitterParam.curvePath(owner, c);
	}

	/** A select of the curves: a new one (named after `name`), the curves under `owner`; plain curves only for `plain` **/
	static function curveSelect(ctx: EditContext2, parent: hide.kit.Element, id: String, owner: Prefab, path: String, name: String, plain: Bool, set: String -> Void) {
		var select = new hide.kit.Select(parent, id);
		var curves : Array<hide.kit.Select.SelectEntry> = [for (c in paramCurves(owner)) if (!plain || c.isPlain()) {
			var path = EmitterParam.curvePath(owner, c);
			{ value: path, label: path };
		}];
		if (path != null && !Lambda.exists(curves, e -> e.value == path))
			curves.push({ value: path, label: path + " (missing)" });
		select.setEntries([{ value: "new", label: "New curve" }, { value: null, label: "Reference", children: curves }]);
		select.value = path;
		select.defaultValue = path;
		select.onValueChange = (_) -> {
			var v : String = select.value;
			if (v == "new")
				AnimEdit.editTree(ctx, owner, () -> set(newCurve(owner, name)));
			else
				set(v);
			ctx.rebuildPrefab(owner);
			ctx.rebuildInspector();
		}
	}

	/**
		The lines of param `def` of `owner` in `parent`, one mode per component among `modes`. An unset component
		shows its default value grayed out: editing it sets it, and a constant set back to its default is unset.
		`set` stores the mode of a component, `onChange` follows each edit. The Spawn and Multiplier fields can be animated (`AnimEdit`).
	**/
	public static function param(ctx: EditContext2, parent: hide.kit.Element, owner: Prefab, def: ModeParamDef, modes: Array<ModeKind>,
			get: Int -> ParamMode, set: (Int, ParamMode) -> Void, onChange: Bool -> Void) {
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
		function setComp(i: Int, m: ParamMode) {
			// no difference between the default value and no value
			if (m != null && m.match(Constant(_)) && Type.enumParameters(m)[0] == def.def[i])
				m = null;
			set(i, m);
		}

		var value = [for (i in 0...dim) get(i)];
		var compName = (i: Int) -> EmitterParam.COMPONENTS[i].toUpperCase();

		function menuEdit(line: hide.kit.Element, f: () -> Void) {
			@:privateAccess line.change({ callback: f, isTemporaryEdit: false, recordUndo: true });
			rebuild();
		}
		function compItems(line: hide.kit.Element, i: Int) : Array<hrt.ui.HuiMenu.MenuItem> {
			var m = get(i);
			var kind = m == null ? Constant : kindOf(m);
			// a constant at its default is shown unset: nothing to remove
			function isSet(j: Int) {
				var c = get(j);
				return c != null && !(c.match(Constant(_)) && Type.enumParameters(c)[0] == def.def[j]);
			}
			var items : Array<hrt.ui.HuiMenu.MenuItem> = [];
			if (dim > 1)
				items.push({ isSeparator: true, label: label + " " + compName(i) });
			if (modes.length > 1) {
				for (mode in modes)
					items.push({ label: hide.kit.Macros.camelToSpaceCase(mode), radio: () -> kind == mode,
						click: () -> {
							// from a mode without a curve, a new one: the curve and the mode in one undo step
							if (mode != Constant && mode != Range && (m == null || m.match(Constant(_) | Range(_)))) {
								var curveName = def.name + (dim == 1 ? "" : compName(i));
								AnimEdit.editTree(ctx, owner, () -> setComp(i, convert(m, mode, def.def[i], () -> newCurve(owner, curveName))));
								rebuild();
							} else
								menuEdit(line, () -> setComp(i, convert(m, mode, def.def[i], () -> null)));
						} });
				items.push({ isSeparator: true });
			}
			items.push({ label: dim == 1 ? "Remove" : "Remove " + compName(i), click: () -> menuEdit(line, () -> setComp(i, null)), enabled: isSet(i) });
			if (dim > 1)
				items.push({ label: "Remove all", click: () -> menuEdit(line, () -> for (j in 0...dim) set(j, null)), enabled: Lambda.exists([for (j in 0...dim) j], isSet) });
			return items;
		}

		// constant components on one line
		var compact = dim > 1 && Lambda.foreach(value, m -> m == null || m.match(Constant(_)));
		var compactLine = null;
		if (compact) {
			compactLine = new hide.kit.Line(parent, def.name);
			compactLine.label = label;
		}
		for (i in 0...dim) {
			var id = def.name + (dim == 1 ? "" : compName(i));
			var suffix = compact ? compName(i) : "";
			var line = compactLine;
			// the elements that have the menu of the component: its value on the line of the vector, its lines otherwise
			var menuOwners : Array<hide.kit.Element> = [];
			if (line == null) {
				line = new hide.kit.Line(parent, id);
				line.label = dim == 1 ? label : label + " " + compName(i);
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
					if (make().match(Constant(_)))
						s.faded = s.value == def.def[i];
				}
				s.onValueChange = (temp) -> {
					onChange(temp);
					if (changed != null) changed();
					// set or unset by the edit: its menu changes
					if (!temp && (get(i) != null) != (m != null))
						ctx.rebuildInspector();
				}
				s.anim = anim;
				return s;
			}

			/**
				A curve editor, and below it on one line the `from` fields (the start of the particle life, at
				the left) and the `to` ones (its end, at the right), with a button swapping them
			**/
			function curve(s: String, from: Array<{ v: () -> Float, set: Float -> Void }>, to: Array<{ v: () -> Float, set: Float -> Void }>, ranges: () -> Array<hide.kit.ParamCurve.ParamRange>, suffix: String) {
				var graph = new hide.kit.ParamCurve(parent, id + "Curve" + suffix, owner, curveFunction(owner, s), ranges(), editableCurve(owner, s), blendFunctions(owner, s));
				var bounds = new hide.kit.Line(parent, id + "Bounds" + suffix);
				bounds.cssClass = "kit-param-bounds";
				// no label: the fields are under the ends of the curve
				bounds.full = true;
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
			function select(parent: hide.kit.Element, sid: String, s: String, set: String -> Void) {
				curveSelect(ctx, parent, sid, owner, s, def.name + (dim == 1 ? "" : compName(i)), m.match(CurveRange(_)), (s) -> {
					set(s);
					apply();
				});
			}
			inline function mid(a: Float, b: Float) return (a + b) * 0.5;

			switch (m) {
				case null:
					var v = def.def[i];
					make = () -> Constant(v);
					slider(line, "value" + suffix, compact ? compName(i) : "", v, v, x -> v = x, animKey()).faded = true;
				case Constant(v):
					make = () -> Constant(v);
					slider(line, "value" + suffix, compact ? compName(i) : "", v, def.def[i], x -> v = x, animKey()).faded = v == def.def[i];
				case Range(min, max):
					make = () -> Range(min, max);
					slider(line, "min", "Min", min, def.def[i], x -> min = x, animKey("min"));
					slider(line, "max", "Max", max, def.def[i], x -> max = x, animKey("max"));
				case Curve(s, from, to):
					make = () -> Curve(s, from, to);
					select(line, "curve0", s, x -> s = x);
					curve(s, [{ v: () -> from, set: x -> from = x }], [{ v: () -> to, set: x -> to = x }], () -> [{ from: from, to: to }], "");
				case RandomCurve(s, fromMin, fromMax, toMin, toMax):
					make = () -> RandomCurve(s, fromMin, fromMax, toMin, toMax);
					select(line, "curve0", s, x -> s = x);
					curve(s, [{ v: () -> fromMin, set: x -> fromMin = x }, { v: () -> fromMax, set: x -> fromMax = x }], [{ v: () -> toMin, set: x -> toMin = x }, { v: () -> toMax, set: x -> toMax = x }],
						() -> [{ from: mid(fromMin, fromMax), to: mid(toMin, toMax) }, { from: fromMin, to: toMin }, { from: fromMax, to: toMax }], "");
				case CurveRange(a, aFrom, aTo, b, bFrom, bTo):
					make = () -> CurveRange(a, aFrom, aTo, b, bFrom, bTo);
					var lineA = new hide.kit.Line(parent, id + "LineA");
					lineA.label = "A";
					menuOwners.push(lineA);
					select(lineA, "curve0", a, x -> a = x);
					curve(a, [{ v: () -> aFrom, set: x -> aFrom = x }], [{ v: () -> aTo, set: x -> aTo = x }], () -> [{ from: aFrom, to: aTo }], "0");
					var lineB = new hide.kit.Line(parent, id + "LineB");
					lineB.label = "B";
					menuOwners.push(lineB);
					select(lineB, "curve1", b, x -> b = x);
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
						s.label = EmitterParam.COMPONENTS[i].toUpperCase();
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
			param(ctx, getCategory(p.groupName), emitter, p, kindModes(p.kind), (i) -> owner.getMode(p.name, i), (i, m) -> owner.setMode(p.name, i, m), (temp) -> changed(p.name, temp));
	}
}

#end
