package hrt.prefab.fx;

import hrt.prefab.fx.EmitterParam;

typedef ParamDef = {
	> hrt.prefab.Props.PropDef,
	?animate: Bool,
	?groupName: String
}

class EmitterHelper {

	public static function isEmitter( p : Prefab ) {
		return p is Emitter || p is Emitter2D;
	}

	public static function getParams( p : Prefab ) : Array<ParamDef> {
		var e = Std.downcast(p, Emitter);
		if( e != null ) return e.getParams();
		var e2 = Std.downcast(p, Emitter2D);
		if( e2 != null ) return e2.getParams();
		return [];
	}

	public static function getModeParams( p : Prefab ) : Array<ModeParamDef> {
		var e = Std.downcast(p, Emitter);
		if( e != null ) return e.getModeParams();
		var e2 = Std.downcast(p, Emitter2D);
		if( e2 != null ) return e2.getModeParams();
		return [];
	}

	/** The mode of the component `comp` of the param `name` of an emitter, or of a shader under an emitter (a particle curve or null) **/
	public static function getMode( p : Prefab, name : String, comp : Int ) : ParamMode {
		var e = Std.downcast(p, Emitter);
		if( e != null ) return e.getMode(name, comp);
		var e2 = Std.downcast(p, Emitter2D);
		if( e2 != null ) return e2.getMode(name, comp);
		var shader = Std.downcast(p, hrt.prefab.Shader);
		if( shader != null ) {
			var c = Lambda.find(shader.particleParams, p -> p.name == name)?.comps[comp];
			return c == null ? null : Curve(c.curve);
		}
		return null;
	}

	/** For a shader, a Constant sets its prop, a Curve its particle curve **/
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
		var param = Lambda.find(shader.particleParams, p -> p.name == name);
		if( param == null ) {
			param = { name: name, comps: [for( _ in 0...size ) null] };
			shader.particleParams.push(param);
		}
		param.comps[comp] = switch( m ) {
			case Curve(curve): { curve: curve };
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
				null;
			case null, _: null;
		}
		if( !Lambda.exists(param.comps, c -> c != null) )
			shader.particleParams.remove(param);
	}

	/** `m.rotate(0, 0, angle)` without the 4 other sin/cos and the full multiply **/
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

	/** `ListSort.sort` (same stable order) of a list about in order but for its first `k` nodes, the particles added since the last sort **/
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
	public static function editParam(ctx: EditContext2, prefab: Prefab, def: ModeParamDef, allowed: Array<ModeKind>, parent: hide.kit.Element) {
		var size = def.def.length;
		var label = def.disp ?? hide.kit.Macros.camelToSpaceCase(def.name);
		var range = switch (def.t) {
			case PFloat(min, max), PVec(_, min, max): { min: min, max: max };
			default: { min: null, max: null };
		}
		var comps = [for (i in 0...size) i];
		var value = [for (i in comps) getMode(prefab, def.name, i)];

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
			var m = getMode(prefab, def.name, i);
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
			setupVectorHeader(line);
		}

		for (i in comps) {
			var menuOwners : Array<hide.kit.Element> = [];
			if (!isCompact) {
				line = new hide.kit.Line(parent, def.name + (size == 1 ? "" : compName(i)));
				line.stealLabel = false;
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

			function selectCurve(path: String) {
				ctx.recordPrefabUndoWithChildren(prefab, () -> {
					setParamMode(prefab, def, i, switch (getMode(prefab, def.name, i)) {
						case RandomCurve(_, from, to): RandomCurve(path, from, to);
						case CurveRange(_): CurveRange(path);
						case null, _: Curve(path);
					});
				});
				ctx.rebuildInspector();
			}

			function curveEditor(path: String, ?spread: hide.kit.Curve.TrackSpread) {
				var g = new hide.kit.Curve(line, "curve", (size == 1 ? label : label + " " + compName(i)) + " - " + prefab.name);
				g.onValueChange = (_) -> ctx.rebuildPrefab(prefab);
				g.onCurveChange = selectCurve;
				if (size > 1)
					menuOwners.push(g);
				var edited = getEditableCurve(prefab, path);
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
				var count = value[i].match(CurveRange(_)) ? 2 : 1;
				var entries : Array<hide.kit.Select.SelectEntry> = [];
				for (c in prefab.children) {
					var curve = Std.downcast(c, hrt.prefab.fx.Curve);
					if (curve == null || !curve.isParticleCurve())
						continue;
					var cpath = EmitterParam.curvePath(prefab, curve);
					if ((curve.isPlain() && curve.datas.length == count) || cpath == path)
						entries.push({ value: cpath, label: cpath });
				}
				if (!Lambda.exists(entries, e -> e.value == path))
					entries.push({ value: path, label: path + " (missing)" });
				g.curvePath = path;
				g.curveChoices = entries;
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
				case Curve(s):
					curveEditor(s);
				case RandomCurve(s, from, to):
					function apply() { setParamMode(prefab, def, i, RandomCurve(s, from, to)); }
					curveEditor(s, { from: { v: () -> from, set: x -> { from = x; apply(); } }, to: { v: () -> to, set: x -> { to = x; apply(); } } });
				case CurveRange(s):
					curveEditor(s);
			}
			for (o in menuOwners)
				o.menuItems = () -> contextMenu(i);
		}
	}

	// Build inspector for an emitter
	public static function edit(ctx: EditContext2, emitter: Prefab, settings: Array<ParamDef>, changed: (name: String, temp: Bool) -> Void) {

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
						continue;
					if (!p.animate)
						widget.anim = null;
					widget.onValueChange = (temp) -> changed(p.name, temp);
			}
		}

		function getAllowedModes(kind: ParamKind) : Array<ModeKind> {
			return switch (kind) {
				case Spawn: [Constant, Range];
				case Particle: [Constant, Range, Curve, RandomCurve, CurveRange];
				case Multiplier: [Constant];
			}
		}

		for (p in getModeParams(emitter))
			editParam(ctx, emitter, p, getAllowedModes(p.kind), getCategory(p.groupName));
	}


	static function compName(i: Int) {
		return EmitterParam.COMPONENTS[i].toUpperCase();
	}

	static function isDefault(def: ModeParamDef, i: Int, m: ParamMode) {
		return switch (m) {
			case null: true;
			case Constant(v): v == def.def[i];
			default: false;
		}
	}

	static function isSet(prefab: Prefab, def: ModeParamDef, i: Int) {
		return !isDefault(def, i, getMode(prefab, def.name, i));
	}

	static function isAnySet(prefab: Prefab, def: ModeParamDef) {
		return Lambda.exists([for (i in 0...def.def.length) i], i -> isSet(prefab, def, i));
	}

	/** A mode set back to the default value of the param unsets it **/
	static function setParamMode(prefab: Prefab, def: ModeParamDef, i: Int, m: ParamMode) {
		setMode(prefab, def.name, i, isDefault(def, i, m) ? null : m);
	}

	static function convert(prefab: Prefab, def: ModeParamDef, i: Int, mode: ModeKind) : ParamMode {
		var base = def.def[i];
		function at(s: String, k: Int, t: Float) { return EmitterParam.resolveCurve(prefab, s)?.datas[k]?.getVal(t) ?? base; }
		function data(src: String, from: Float, to: Float, shiftFrom = 0., shiftTo = 0.) { return newModeData(prefab, src, from, to, shiftFrom, shiftTo); }
		function curve(datas: Array<hrt.impl.Curve>) { return newModeCurve(prefab, def, i, datas); }
		var m = getMode(prefab, def.name, i) ?? Constant(base);
		var f0 = base, f1 = base, t0 = base, t1 = base;
		switch (m) {
			case Constant(v): f0 = f1 = t0 = t1 = v;
			case Range(min, max): f0 = t0 = min; f1 = t1 = max;
			case Curve(s): f0 = f1 = at(s, 0, 0); t0 = t1 = at(s, 0, 1);
			case RandomCurve(s, from, to): f0 = at(s, 0, 0) - from; f1 = at(s, 0, 0) + from; t0 = at(s, 0, 1) - to; t1 = at(s, 0, 1) + to;
			case CurveRange(s): f0 = at(s, 0, 0); t0 = at(s, 0, 1); f1 = at(s, 1, 0); t1 = at(s, 1, 1);
		}
		var fm = (f0 + f1) * 0.5, tm = (t0 + t1) * 0.5;
		return switch [mode, m] {
			case [Constant, _]: Constant(tm);
			case [Range, _]: Range(t0, t1);
			case [Curve, Curve(_)]: m;
			case [Curve, CurveRange(s)]: Curve(curve([data(s, 0, 1)]));
			case [Curve, RandomCurve(s, _)]: Curve(s);
			case [Curve, _]: Curve(curve([data(null, fm, tm)]));
			case [RandomCurve, RandomCurve(_)]: m;
			case [RandomCurve, Curve(s)]: RandomCurve(s, 0, 0);
			case [RandomCurve, CurveRange(s)]: RandomCurve(curve([data(s, 0, 1)]), 0, 0);
			case [RandomCurve, _]: RandomCurve(curve([data(null, fm, tm)]), (f1 - f0) * 0.5, (t1 - t0) * 0.5);
			case [CurveRange, CurveRange(_)]: m;
			case [CurveRange, Curve(s)]: CurveRange(curve([data(s, 0, 1), data(null, f1, t1)]));
			case [CurveRange, RandomCurve(s, from, to)]: CurveRange(curve([data(s, 0, 1, -from, -to), data(s, 0, 1, from, to)]));
			case [CurveRange, _]: CurveRange(curve([data(null, f0, t0), data(null, f1, t1)]));
		}
	}

	static function newModeCurve(owner: Prefab, def: ModeParamDef, i: Int, datas: Array<hrt.impl.Curve>) : String {
		var c = new Curve(owner, owner.shared);
		var base = def.name + (def.def.length == 1 ? "" : compName(i)) + "Curve";
		var name = base;
		var n = 1;
		while (Lambda.exists(owner.children, p -> p.name != null && p.name.toLowerCase() == name.toLowerCase())) {
			name = base + n;
			n++;
		}
		c.name = name;
		c.datas = datas;
		return EmitterParam.curvePath(owner, c);
	}

	/**
		The keys of the curve `src` remapped from 0..1 to `from`..`to`, then shifted by `lerp(shiftFrom, shiftTo, t)`, or a line
		from `from` to `to` without `src`
	**/
	static function newModeData(owner: Prefab, src: String, from: Float, to: Float, shiftFrom = 0., shiftTo = 0.) : hrt.impl.Curve {
		var d = new hrt.impl.Curve();
		var s = src == null ? null : getEditableCurve(owner, src);
		if (s == null) {
			d.addKey(0, from, Linear);
			d.addKey(1, to, Linear);
			return d;
		}
		@:privateAccess d.copyFromDynamic(hrt.prefab.Diff.deepCopy(s.data.copyToDynamic(null)));
		for (k in d.keys) {
			k.value = hxd.Math.lerp(from, to, k.value) + hxd.Math.lerp(shiftFrom, shiftTo, k.time);
			for (h in [k.prevHandle, k.nextHandle])
				if (h != null)
					h.dv = h.dv * (to - from) + (shiftTo - shiftFrom) * h.dt;
		}
		return d;
	}

	static function getModeCurves(owner: Prefab) : Array<Curve> {
		var modes : Array<ParamMode> = [];
		for (p in getModeParams(owner))
			for (i in 0...p.def.length)
				modes.push(getMode(owner, p.name, i));
		var shader = Std.downcast(owner, hrt.prefab.Shader);
		if (shader != null)
			for (p in shader.particleParams)
				for (c in p.comps)
					if (c != null)
						modes.push(Curve(c.curve));
		var paths = [];
		for (m in modes)
			switch (m) {
				case Curve(s), RandomCurve(s, _), CurveRange(s): paths.push(s);
				case null, Constant(_), Range(_):
			}
		var curves = [];
		for (path in paths) {
			var c = owner.locatePrefab(path)?.to(hrt.prefab.fx.Curve);
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

	static function getEditableCurve(owner: Prefab, path: String) : Curve {
		var c = EmitterParam.resolveCurve(owner, path);
		return c != null && c.isPlain() ? c : null;
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

	/** Not the one of a trail or a sub-emitter it is under **/
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
