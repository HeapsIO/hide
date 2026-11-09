package hrt.prefab.fx;

import hrt.prefab.fx.EmitterParam;

typedef PropertyDef = {
	> hrt.prefab.Props.PropDef,
	?animate: Bool,
	?groupName: String
}

class EmitterHelper {

	public static function isEmitter( p : Prefab ) {
		return p is Emitter || p is Emitter2D;
	}

	public static function getProperties( p : Prefab ) : Array<PropertyDef> {
		var e = Std.downcast(p, Emitter);
		if( e != null ) return e.getProperties();
		var e2 = Std.downcast(p, Emitter2D);
		if( e2 != null ) return e2.getProperties();
		return [];
	}

	public static function getParams( p : Prefab ) : Array<ParamDef> {
		var e = Std.downcast(p, Emitter);
		if( e != null ) return e.getParams();
		var e2 = Std.downcast(p, Emitter2D);
		if( e2 != null ) return e2.getParams();
		return [];
	}

	public static function getFieldsOrder( p : Prefab ) : Array<String> {
		var e = Std.downcast(p, Emitter);
		if( e != null ) return e.getFieldsOrder();
		var e2 = Std.downcast(p, Emitter2D);
		if( e2 != null ) return e2.getFieldsOrder();
		return [];
	}

	public static function getMode( p : Prefab, name : String, comp : Int ) : ParamMode {
		var e = Std.downcast(p, Emitter);
		if( e != null ) return e.getMode(name, comp);
		var e2 = Std.downcast(p, Emitter2D);
		if( e2 != null ) return e2.getMode(name, comp);
		var shader = Std.downcast(p, hrt.prefab.Shader);
		if( shader != null ) {
			var pp = shader.particleParams;
			return pp.contains(name + ":" + EmitterParam.COMPONENTS[comp]) || (comp == 0 && pp.contains(name)) ? Curve : null;
		}
		return null;
	}

	public static function setMode( p : Prefab, name : String, comp : Int, m : ParamMode ) {
		var e = Std.downcast(p, Emitter);
		if( e != null ) {
			e.setMode(name, comp, m);
			return;
		}
		var e2 = Std.downcast(p, Emitter2D);
		if( e2 != null ) {
			e2.setMode(name, comp, m);
			return;
		}
		var shader = Std.downcast(p, hrt.prefab.Shader);
		if( shader == null )
			throw "Not an emitter or a shader: " + p.getAbsPath(true);
		var size = EmitterParam.getParamSize(Lambda.find(shader.getShaderDefinition().data.vars, v -> v.name == name));
		var key = EmitterParam.curveName(name, size, comp);
		shader.particleParams.remove(key);
		switch( m ) {
			case Curve:
				shader.particleParams.push(key);
				shader.particleParams.sort(Reflect.compare);
			case Constant(k):
				if( size == 1 )
					Reflect.setField(shader.props, name, k);
				else {
					var prop : Array<Dynamic> = Reflect.field(shader.props, name);
					if( !Std.isOfType(prop, Array) ) {
						prop = [for( j in 0...size ) EmitterParam.baseComponent(prop, size, j)];
						Reflect.setField(shader.props, name, prop);
					}
					prop[comp] = k;
				}
			case null, _:
		}
	}

	public static inline function rotateZ( m : h3d.Matrix, angle : Float ) {
		var c = Math.cos(angle);
		var s = Math.sin(angle);
		var a = m._11, b = m._12;
		m._11 = a * c - b * s; m._12 = a * s + b * c;
		a = m._21; b = m._22;
		m._21 = a * c - b * s; m._22 = a * s + b * c;
		a = m._31; b = m._32;
		m._31 = a * c - b * s; m._32 = a * s + b * c;
		a = m._41; b = m._42;
		m._41 = a * c - b * s; m._42 = a * s + b * c;
	}

	// Optim: up to 4x faster than a full sort when < 5% of the particles are new each frame
	public static inline function depthSort<T:{prev:T, next:T}>( head : T, k : Int, budget : Int, cmp : T -> T -> Int ) : T {
		var rest = head;
		for( i in 0...k ) {
			if( rest == null ) break;
			rest = rest.next;
		}
		var fresh : T = null;
		if( rest != head ) {
			fresh = head;
			if( rest != null ) {
				rest.prev.next = null;
				rest.prev = null;
			}
			fresh = haxe.ds.ListSort.sort(fresh, cmp);
		}
		return merge(fresh, insertionSort(rest, budget, cmp), cmp);
	}

	static inline function insertionSort<T:{prev:T, next:T}>( head : T, budget : Int, cmp : T -> T -> Int ) : T {
		var cur = head == null ? null : head.next;
		while( cur != null ) {
			var next = cur.next;
			var p = cur.prev;
			if( cmp(p, cur) > 0 ) {
				p.next = next;
				if( next != null )
					next.prev = p;
				while( p.prev != null && cmp(p.prev, cur) > 0 && --budget >= 0 )
					p = p.prev;
				cur.prev = p.prev;
				cur.next = p;
				if( p.prev != null )
					p.prev.next = cur;
				else
					head = cur;
				p.prev = cur;
				if( budget < 0 ) {
					head = haxe.ds.ListSort.sort(head, cmp);
					break;
				}
			}
			cur = next;
		}
		// `ListSort.sort` sets the `prev` of the head to the tail
		if( head != null )
			head.prev = null;
		return head;
	}

	static inline function merge<T:{prev:T, next:T}>( a : T, b : T, cmp : T -> T -> Int ) : T {
		var head : T = null, tail : T = null;
		while( a != null || b != null ) {
			var e;
			if( b == null || (a != null && cmp(a, b) <= 0) ) {
				e = a;
				a = a.next;
			} else {
				e = b;
				b = b.next;
			}
			if( tail == null )
				head = e;
			else
				tail.next = e;
			e.prev = tail;
			tail = e;
		}
		return head;
	}

	#if domkit

	// Build inspector for an emitter parameter
	public static function editParam(ctx: EditContext2, prefab: Prefab, def: ParamDef, allowed: Array<ModeKind>, parent: hide.kit.Element) {
		var size = def.def.length;
		var label = def.disp ?? hide.kit.Macros.camelToSpaceCase(def.name);
		var range = switch (def.t) {
			case PFloat(min, max), PVec(_, min, max): { min: min, max: max };
			default: { min: null, max: null };
		}
		var comps = [for (i in 0...size) i];
		var value = [for (i in comps) shownMode(prefab, def, i)];

		function applyMode(comps: Array<Int>, mode: Null<ModeKind>) {
			var before = getModeCurves(prefab);
			ctx.recordPrefabUndoWithChildren(prefab, () -> {
				for (i in comps)
					setParamMode(prefab, def, i, mode == null ? null : convert(prefab, def, i, mode));
				removeUnusedModeCurves(prefab, before);
			});
			ctx.rebuildInspector();
		}

		function contextMenu(i: Int) : Array<hrt.ui.HuiMenu.MenuItem> {
			var m = shownMode(prefab, def, i);
			var kind : ModeKind = m == null ? Constant : cast m.getName();
			var items : Array<hrt.ui.HuiMenu.MenuItem> = [];
			if (size > 1)
				items.push({ isSeparator: true, label: label + " " + compName(i) });
			if (allowed.length > 1) {
				for (mode in allowed)
					items.push({ label: hide.kit.Macros.camelToSpaceCase(mode), radio: () -> kind == mode, click: () -> applyMode([i], mode) });
				items.push({ isSeparator: true });
			}
			items.push({ label: size == 1 ? "Remove" : "Remove " + compName(i), click: () -> applyMode([i], null), enabled: isSet(prefab, def, i) });
			return items;
		}

		function setupVectorHeader(line: hide.kit.Line) {
			line.label = label;
			line.unset = !isAnySet(prefab, def);
			line.menuItems = () -> [
				{ isSeparator: true, label: label },
				{ label: "Remove all", click: () -> applyMode(comps, null), enabled: isAnySet(prefab, def) },
			];
		}

		var line = null;
		var isCompact = size > 1 && Lambda.foreach(value, m -> m == null || m.match(Constant(_)));
		if (isCompact) {
			line = new hide.kit.Line(parent, def.name);
			line.stealLabel = false;
			line.tooltip = def.desc;
			setupVectorHeader(line);
		}

		for (i in comps) {
			var menuOwners : Array<hide.kit.Element> = [];
			if (!isCompact) {
				line = new hide.kit.Line(parent, def.name + (size == 1 ? "" : compName(i)));
				line.stealLabel = false;
				line.tooltip = def.desc;
				if (size == 1) {
					line.label = label;
					line.unset = !isSet(prefab, def, i);
					menuOwners.push(line);
				} else {
					if (i == 0)
						setupVectorHeader(line);
					var name = new hide.kit.Text(line, "comp", compName(i));
					name.classList.push("kit-param-comp");
					name.unset = !isSet(prefab, def, i);
					menuOwners.push(name);
				}
			}
			var wasSet = isSet(prefab, def, i);
			function slider(sid: String, label: String, value: Float, ?field: String) {
				var s = new hide.kit.Slider<Float>(line, sid);
				if (size > 1)
					menuOwners.push(s);
				if (def.kind != Particle)
					s.anim = EmitterParam.animKey(def, i, field);
				s.label = label;
				s.value = value;
				s.min = range.min;
				s.max = range.max;
				s.defaultValue = def.def[i];
				s.showRange = range.min != null && range.max != null;
				s.onValueChange = (temp) -> {
					ctx.rebuildPrefab(prefab);
					if (!temp && isSet(prefab, def, i) != wasSet)
						ctx.rebuildInspector();
				}
				return s;
			}

			function curveEditor(?spread: hide.kit.Curve.TrackSpread, ?onSpreadChange: hide.kit.Curve.TrackSpread -> Void) {
				var g = new hide.kit.Curve(line, "curve", (size == 1 ? label : label + " " + compName(i)) + " - " + prefab.name);
				g.onValueChange = (_) -> ctx.rebuildPrefab(prefab);
				if (onSpreadChange != null)
					g.onSpreadChange = onSpreadChange;
				if (size > 1)
					menuOwners.push(g);
				var edited = getEditableCurve(prefab, EmitterParam.animKey(def, i));
				if (edited == null)
					g.addTrack(null, spread);
				else
					for (d in edited.datas)
						g.addTrack(d, spread);
				if (g.tracks.length == 2) {
					g.addBand(g.tracks[0], g.tracks[1]);
					g.tracks[0].name = "Min";
					g.tracks[1].name = "Max";
				}
			}

			switch (value[i]) {
				case null, Constant(_):
					var v = switch (value[i]) {
						case Constant(c): c;
						case null, _: def.def[i];
					}

					var s = slider("value" + (isCompact ? compName(i) : ""), isCompact ? compName(i) : "", v);
					s.unset = !wasSet;
					@:privateAccess s.onFieldChange = (_) -> {
						setParamMode(prefab, def, i, Constant(s.value));
						s.unset = s.value == def.def[i];
					}

				case Range(min, max):
					var minSlider = slider("min", "Min", min, "min");
					var maxSlider = slider("max", "Max", max, "max");
					function bound() {
						minSlider.max = range.max == null ? maxSlider.value : Math.min(range.max, maxSlider.value);
						maxSlider.min = range.min == null ? minSlider.value : Math.max(range.min, minSlider.value);
					}

					function apply() {
						bound();
						setParamMode(prefab, def, i, Range(minSlider.value, maxSlider.value));
					}

					@:privateAccess minSlider.onFieldChange = (_) -> {
						minSlider.value = Math.min(minSlider.value, maxSlider.value);
						apply();
					}
					@:privateAccess maxSlider.onFieldChange = (_) -> {
						maxSlider.value = Math.max(maxSlider.value, minSlider.value);
						apply();
					}
					bound();
				case Curve, CurveRange:
					curveEditor();
				case RandomCurve(spreadMin, spreadMax):
					curveEditor({ min: spreadMin, max: spreadMax }, sp -> setParamMode(prefab, def, i, RandomCurve(sp.min, sp.max)));
			}
			for (o in menuOwners)
				o.menuItems = () -> contextMenu(i);
		}
	}

	// Build inspector for an emitter
	public static function edit(ctx: EditContext2, emitter: Prefab, properties: Array<PropertyDef>, changed: (name: String, temp: Bool) -> Void) {

		var categories = new Map<String, hide.kit.Category>();
		function getCategory(name: String) {
			var cat = categories.get(name);
			if (cat == null) {
				cat = new hide.kit.Category(ctx.root, name, name);
				categories.set(name, cat);
			}
			return cat;
		}

		var params = getParams(emitter);
		for (name in getFieldsOrder(emitter)) {
			var property = Lambda.find(properties, p -> p.name == name);
			if (property != null) {
				editProperty(getCategory(property.groupName ?? "Emitter"), emitter, property, changed);
				continue;
			}
			var param = Lambda.find(params, p -> p.name == name);
			if (param != null)
				editParam(ctx, emitter, param, getAllowedModes(param.kind), getCategory(param.groupName));
		}
	}

	static function editProperty(cat: hide.kit.Category, emitter: Prefab, p: PropertyDef, changed: (name: String, temp: Bool) -> Void) {
		switch (p.t) {
			case PVec(n, min, max) if (p.name.toLowerCase().indexOf("color") < 0):
				var line = new hide.kit.Line(cat, p.name);
				line.label = p.disp ?? hide.kit.Macros.camelToSpaceCase(p.name);
				line.tooltip = p.desc;
				var vec : Array<Float> = Reflect.field(emitter, p.name);
				for (i in 0...n) {
					var s = new hide.kit.Slider<Float>(line, p.name + i);
					s.label = compName(i);
					s.value = vec[i];
					s.min = min;
					s.max = max;
					s.showRange = min != null && max != null;
					@:privateAccess s.onFieldChange = (_) -> vec[i] = s.value;
					s.onValueChange = (temp) -> changed(p.name, temp);
				}
			default:
				var widget = cat.buildProp(p, emitter);
				if (widget == null)
					return;
				if (!p.animate)
					widget.anim = null;
				widget.onValueChange = (temp) -> changed(p.name, temp);
		}
	}

	static function getAllowedModes(kind: ParamKind) : Array<ModeKind> {
		return switch (kind) {
			case Spawn: [Constant, Range];
			case Particle: [Constant, Range, Curve, RandomCurve, CurveRange];
		}
	}


	static function compName(i: Int) {
		return EmitterParam.COMPONENTS[i].toUpperCase();
	}

	static function isDefault(def: ParamDef, i: Int, m: ParamMode) {
		return switch (m) {
			case null: true;
			case Constant(v): v == def.def[i];
			default: false;
		}
	}

	// a curve mode whose curve was deleted shows the default value
	static function shownMode(prefab: Prefab, def: ParamDef, i: Int) {
		return EmitterParam.saved(prefab, def, i, getMode(prefab, def.name, i));
	}

	static function isSet(prefab: Prefab, def: ParamDef, i: Int) {
		return !isDefault(def, i, shownMode(prefab, def, i));
	}

	static function isAnySet(prefab: Prefab, def: ParamDef) {
		return Lambda.exists([for (i in 0...def.def.length) i], i -> isSet(prefab, def, i));
	}

	static function setParamMode(prefab: Prefab, def: ParamDef, i: Int, m: ParamMode) {
		setMode(prefab, def.name, i, isDefault(def, i, m) ? null : m);
	}

	static function convert(prefab: Prefab, def: ParamDef, i: Int, mode: ModeKind) : ParamMode {
		var base = def.def[i];
		var key = EmitterParam.animKey(def, i);
		var cur = getEditableCurve(prefab, key);
		function at(k: Int, t: Float) { return cur?.datas[k]?.getVal(t) ?? base; }
		// the keys of the current curve remapped from 0..1 to `from`..`to`, or a line
		function data(src: Bool, from: Float, to: Float) { return newModeData(src ? cur : null, from, to); }
		// the spread of a RandomCurve, `spread + slope * value`
		function spread(spreadMin: Float, spreadMax: Float) {
			var c = cur?.datas[0];
			return EmitterParam.spreadLine(c == null ? { min: base, max: base } : c.getValueRange(), spreadMin, spreadMax);
		}
		function curve(datas: Array<hrt.impl.Curve>) { setModeCurve(prefab, key, datas); }
		var m = shownMode(prefab, def, i) ?? Constant(base);
		var f0 = base, f1 = base, t0 = base, t1 = base;
		switch (m) {
			case Constant(v): f0 = f1 = t0 = t1 = v;
			case Range(min, max): f0 = t0 = min; f1 = t1 = max;
			case Curve: f0 = f1 = at(0, 0); t0 = t1 = at(0, 1);
			case RandomCurve(spreadMin, spreadMax):
				var l = spread(spreadMin, spreadMax), v0 = at(0, 0), v1 = at(0, 1);
				var a0 = l.spread + l.slope * v0, a1 = l.spread + l.slope * v1;
				f0 = v0 - a0; f1 = v0 + a0; t0 = v1 - a1; t1 = v1 + a1;
			case CurveRange: f0 = at(0, 0); t0 = at(0, 1); f1 = at(1, 0); t1 = at(1, 1);
		}
		var fm = (f0 + f1) * 0.5, tm = (t0 + t1) * 0.5;
		return switch [mode, m] {
			case [Constant, _]: Constant(tm);
			case [Range, _]: Range(t0, t1);
			case [Curve, Curve]: m;
			case [Curve, CurveRange]: curve([data(true, 0, 1)]); Curve;
			case [Curve, RandomCurve(_)]: Curve;
			case [Curve, _]: curve([data(false, fm, tm)]); Curve;
			case [RandomCurve, RandomCurve(_)]: m;
			case [RandomCurve, Curve]: RandomCurve(0, 0);
			case [RandomCurve, CurveRange]: curve([data(true, 0, 1)]); RandomCurve(0, 0);
			// a line from fm to tm: `spreadMin` is the spread at its lowest end
			case [RandomCurve, _]:
				curve([data(false, fm, tm)]);
				fm <= tm ? RandomCurve((f1 - f0) * 0.5, (t1 - t0) * 0.5) : RandomCurve((t1 - t0) * 0.5, (f1 - f0) * 0.5);
			case [CurveRange, CurveRange]: m;
			case [CurveRange, Curve]: curve([data(true, 0, 1), data(false, f1, t1)]); CurveRange;
			// v -+ (spread + slope * v): the values of the curve remapped
			case [CurveRange, RandomCurve(spreadMin, spreadMax)]:
				var l = spread(spreadMin, spreadMax);
				curve([data(true, -l.spread, 1 - l.slope - l.spread), data(true, l.spread, 1 + l.slope + l.spread)]);
				CurveRange;
			case [CurveRange, _]: curve([data(false, f0, t0), data(false, f1, t1)]); CurveRange;
		}
	}

	static function setModeCurve(owner: Prefab, name: String, datas: Array<hrt.impl.Curve>) {
		var c = hrt.prefab.fx.Curve.getCurve(owner, name);
		if (c == null) {
			c = new hrt.prefab.fx.Curve(owner, owner.shared);
			c.name = name;
		}
		c.datas = datas;
		c.blendMode = datas.length == 2 ? hrt.prefab.fx.Curve.CurveBlendMode.Range : None;
		c.param = null;
		c.refPath = null;
	}

	static function newModeData(src: Curve, from: Float, to: Float) : hrt.impl.Curve {
		var d = new hrt.impl.Curve();
		if (src == null) {
			d.addKey(0, from, Linear);
			d.addKey(1, to, Linear);
			return d;
		}
		@:privateAccess d.copyFromDynamic(hrt.prefab.Diff.deepCopy(src.data.copyToDynamic(null)));
		for (k in d.keys) {
			k.value = hxd.Math.lerp(from, to, k.value);
			for (h in [k.prevHandle, k.nextHandle])
				if (h != null)
					h.dv *= to - from;
		}
		return d;
	}

	static function getModeCurves(owner: Prefab) : Array<Curve> {
		var names = [];
		var shader = Std.downcast(owner, hrt.prefab.Shader);
		if (shader != null)
			names = shader.particleParams.copy();
		else
			for (p in getParams(owner))
				for (i in 0...p.def.length)
					if (EmitterParam.isCurveMode(getMode(owner, p.name, i)))
						names.push(EmitterParam.animKey(p, i));
		var curves = [];
		for (n in names) {
			var c = hrt.prefab.fx.Curve.getCurve(owner, n);
			if (c != null)
				curves.push(c);
		}
		return curves;
	}

	static function removeUnusedModeCurves(owner: Prefab, before: Array<Curve>) {
		var after = getModeCurves(owner);
		for (c in before)
			if (!after.contains(c))
				c.remove();
	}

	static function getEditableCurve(owner: Prefab, name: String) : Curve {
		var c = hrt.prefab.fx.Curve.getCurve(owner, name);
		return c != null && (c.isPlain() || c.blendMode == hrt.prefab.fx.Curve.CurveBlendMode.Range) ? c : null;
	}

	// Build inspector for the params of a shader under an emitter, false if the shader is not under one
	public static function editParticleShader(ctx: EditContext2, shader: hrt.prefab.Shader, props: Array<hrt.prefab.Props.PropDef>, parent: hide.kit.Element) : Bool {
		if (getParticleEmitter(shader) == null)
			return false;
		var shaderDef = shader.getShaderDefinition();
		for (prop in props) {
			var v = Lambda.find(shaderDef.data.vars, v -> v.name == prop.name);
			var size = EmitterParam.getParamSize(v);
			if (size == 0) {
				parent.buildProp(prop, shader.props);
				continue;
			}
			var value : Dynamic = Reflect.field(shader.props, prop.name);
			var base = [for (i in 0...size) EmitterParam.baseComponent(value, size, i)];
			var t : hrt.prefab.Props.PropType = switch (prop.t) {
				case PFloat(_), PVec(_): prop.t;
				case PInt(min, max): PFloat(min, max);
				default: PFloat(0, 1);
			}
			editParam(ctx, shader, { name: prop.name, t: t, def: base, kind: Particle, groupName: null }, [Constant, Curve], parent);
		}
		return true;
	}

	// stops at a trail: its shaders are not particle shaders
	static function getParticleEmitter(shader: hrt.prefab.Shader) : Emitter {
		var p = shader.parent;
		while (p != null && !(p is Emitter) && !(p is hrt.prefab.l3d.Trails))
			p = p.parent;
		return Std.downcast(p, Emitter);
	}

	#end
}

#if domkit

enum abstract ModeKind(String) to String {
	var Constant;
	var Range;
	var Curve;
	var RandomCurve;
	var CurveRange;
}

#end
