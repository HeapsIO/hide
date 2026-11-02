package hrt.prefab.fx;

import hrt.prefab.fx.EmitterParam;

typedef ParamDef = {
	> hrt.prefab.Props.PropDef,
	?animate: Bool,
	?groupName: String
}

class EmitterHelper {

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
	public static function editParam(ctx: EditContext2, prefab: Prefab, owner: ParamModes, def: ModeParamDef, allowed: Array<ModeKind>, parent: hide.kit.Element) {
		var size = def.def.length;
		var label = def.disp ?? hide.kit.Macros.camelToSpaceCase(def.name);
		var range = switch (def.t) {
			case PFloat(min, max), PVec(_, min, max): { min: min, max: max };
			default: { min: null, max: null };
		}
		var comps = [for (i in 0...size) i];
		var value = [for (i in comps) owner.getMode(def.name, i)];

		function applyMode(comps: Array<Int>, mode: Null<ModeKind>) {
			var before = getModeCurves(prefab);
			ctx.recordPrefabUndoWithChildren(prefab, () -> {
				for (i in comps)
					setMode(owner, def, i, mode == null ? null : convert(prefab, owner, def, i, mode));
				removeUnusedModeCurves(prefab, before);
			});
			ctx.rebuildInspector();
		}

		function contextMenu(i: Int) : Array<hrt.ui.HuiMenu.MenuItem> {
			var m = owner.getMode(def.name, i);
			var kind : ModeKind = m == null ? Constant : cast m.getName();
			var items : Array<hrt.ui.HuiMenu.MenuItem> = [];
			if (size > 1)
				items.push({ isSeparator: true, label: label + " " + compName(i) });
			if (allowed.length > 1) {
				for (mode in allowed)
					items.push({ label: hide.kit.Macros.camelToSpaceCase(mode), radio: () -> kind == mode, click: () -> applyMode([i], mode) });
				items.push({ isSeparator: true });
			}
			items.push({ label: size == 1 ? "Remove" : "Remove " + compName(i), click: () -> applyMode([i], null), enabled: isSet(owner, def, i) });
			return items;
		}

		function setupVectorHeader(line: hide.kit.Line) {
			line.label = label;
			line.unset = !isAnySet(owner, def);
			line.menuItems = () -> [
				{ isSeparator: true, label: label },
				{ label: "Remove all", click: () -> applyMode(comps, null), enabled: isAnySet(owner, def) },
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
					line.unset = !isSet(owner, def, i);
					menuOwners.push(line);
				} else {
					if (i == 0)
						setupVectorHeader(line);
					var name = new hide.kit.Text(line, "comp", compName(i));
					name.classList.push("kit-param-comp");
					name.unset = !isSet(owner, def, i);
					menuOwners.push(name);
				}
			}
			var wasSet = isSet(owner, def, i);
			function slider(sid: String, label: String, value: Float) {
				var s = new hide.kit.Slider<Float>(line, sid);
				if (size > 1)
					menuOwners.push(s);
				s.label = label;
				s.value = value;
				s.min = range.min;
				s.max = range.max;
				s.defaultValue = def.def[i];
				s.showRange = range.min != null && range.max != null;
				s.onValueChange = (temp) -> {
					ctx.rebuildPrefab(prefab);
					if (!temp && isSet(owner, def, i) != wasSet)
						ctx.rebuildInspector();
				}
				return s;
			}

			function selectCurve(path: String) {
				ctx.recordPrefabUndoWithChildren(prefab, () -> {
					setMode(owner, def, i, switch (owner.getMode(def.name, i)) {
						case RandomCurve(_, f0, f1, t0, t1): RandomCurve(path, f0, f1, t0, t1);
						case CurveRange(_): CurveRange(path);
						case null, _: Curve(path);
					});
				});
				ctx.rebuildInspector();
			}

			function curveEditor(path: String, ?ranges: Array<hide.kit.Curve.TrackRange>) {
				var g = new hide.kit.Curve(line, "curve", (size == 1 ? label : label + " " + compName(i)) + " - " + prefab.name);
				g.onValueChange = (_) -> ctx.rebuildPrefab(prefab);
				g.onCurveChange = selectCurve;
				if (size > 1)
					menuOwners.push(g);
				var edited = getEditableCurve(prefab, path);
				if (edited == null)
					g.addTrack(null, ranges);
				else
					for (d in edited.datas)
						g.addTrack(d, ranges);
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
						setMode(owner, def, i, Constant(s.value));
						s.unset = s.value == def.def[i];
					}

				case Range(min, max):
					var minSlider = slider("min", "Min", min);
					var maxSlider = slider("max", "Max", max);
					function bound() {
						minSlider.max = range.max == null ? maxSlider.value : Math.min(range.max, maxSlider.value);
						maxSlider.min = range.min == null ? minSlider.value : Math.max(range.min, minSlider.value);
					}

					function apply() {
						bound();
						setMode(owner, def, i, Range(minSlider.value, maxSlider.value));
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
				case RandomCurve(s, fromMin, fromMax, toMin, toMax):
					function apply() { setMode(owner, def, i, RandomCurve(s, fromMin, fromMax, toMin, toMax)); }
					curveEditor(s, [
						{ from: { v: () -> fromMin, set: x -> { fromMin = x; apply(); } }, to: { v: () -> toMin, set: x -> { toMin = x; apply(); } } },
						{ from: { v: () -> fromMax, set: x -> { fromMax = x; apply(); } }, to: { v: () -> toMax, set: x -> { toMax = x; apply(); } } },
					]);
				case CurveRange(s):
					curveEditor(s);
			}
			for (o in menuOwners)
				o.menuItems = () -> contextMenu(i);
		}
	}

	// Build inspector for an emitter
	public static function edit(ctx: EditContext2, owner: BaseEmitter, settings: Array<ParamDef>, changed: (name: String, temp: Bool) -> Void) {
		var emitter : Prefab = cast owner;

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

		for (p in owner.getModeParams())
			editParam(ctx, emitter, owner, p, getAllowedModes(p.kind), getCategory(p.groupName));
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

	static function isSet(owner: ParamModes, def: ModeParamDef, i: Int) {
		return !isDefault(def, i, owner.getMode(def.name, i));
	}

	static function isAnySet(owner: ParamModes, def: ModeParamDef) {
		return Lambda.exists([for (i in 0...def.def.length) i], i -> isSet(owner, def, i));
	}

	static function setMode(owner: ParamModes, def: ModeParamDef, i: Int, m: ParamMode) {
		owner.setMode(def.name, i, isDefault(def, i, m) ? null : m);
	}

	static function convert(prefab: Prefab, owner: ParamModes, def: ModeParamDef, i: Int, mode: ModeKind) : ParamMode {
		var base = def.def[i];
		function at(s: String, k: Int, t: Float) { return EmitterParam.resolveCurve(prefab, s)?.datas[k]?.getVal(t) ?? base; }
		function data(src: String, from: Float, to: Float) { return newModeData(prefab, src, from, to); }
		function curve(datas: Array<hrt.impl.Curve>) { return newModeCurve(prefab, def, i, datas); }
		var m = owner.getMode(def.name, i) ?? Constant(base);
		var f0 = base, f1 = base, t0 = base, t1 = base;
		switch (m) {
			case Constant(v): f0 = f1 = t0 = t1 = v;
			case Range(min, max): f0 = t0 = min; f1 = t1 = max;
			case Curve(s): f0 = f1 = at(s, 0, 0); t0 = t1 = at(s, 0, 1);
			case RandomCurve(_, a, b, c, d): f0 = a; f1 = b; t0 = c; t1 = d;
			case CurveRange(s): f0 = at(s, 0, 0); t0 = at(s, 0, 1); f1 = at(s, 1, 0); t1 = at(s, 1, 1);
		}
		var fm = (f0 + f1) * 0.5, tm = (t0 + t1) * 0.5;
		return switch [mode, m] {
			case [Constant, _]: Constant(tm);
			case [Range, _]: Range(t0, t1);
			case [Curve, Curve(_)]: m;
			case [Curve, CurveRange(s)]: Curve(curve([data(s, 0, 1)]));
			case [Curve, RandomCurve(s, _)]: Curve(curve([data(s, fm, tm)]));
			case [Curve, _]: Curve(curve([data(null, fm, tm)]));
			case [RandomCurve, RandomCurve(_)]: m;
			case [RandomCurve, Curve(s)]: RandomCurve(s, 0, 0, 1, 1);
			case [RandomCurve, CurveRange(s)]: RandomCurve(curve([data(s, 0, 1)]), 0, 0, 1, 1);
			case [RandomCurve, _]: RandomCurve(curve([data(null, 0, 1)]), f0, f1, t0, t1);
			case [CurveRange, CurveRange(_)]: m;
			case [CurveRange, Curve(s)]: CurveRange(curve([data(s, 0, 1), data(null, f1, t1)]));
			case [CurveRange, RandomCurve(s, _)]: CurveRange(curve([data(s, f0, t0), data(s, f1, t1)]));
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

	/** The keys of the curve `src` remapped from 0..1 to `from`..`to`, or a line from `from` to `to` without `src` **/
	static function newModeData(owner: Prefab, src: String, from: Float, to: Float) : hrt.impl.Curve {
		var d = new hrt.impl.Curve();
		var s = src == null ? null : getEditableCurve(owner, src);
		if (s == null) {
			d.addKey(0, from, Linear);
			d.addKey(1, to, Linear);
			return d;
		}
		@:privateAccess d.copyFromDynamic(hrt.prefab.Diff.deepCopy(s.data.copyToDynamic(null)));
		for (k in d.keys) {
			k.value = hxd.Math.lerp(from, to, k.value);
			for (h in [k.prevHandle, k.nextHandle])
				if (h != null)
					h.dv *= to - from;
		}
		return d;
	}

	static function getModeCurves(owner: Prefab) : Array<Curve> {
		var modes : Array<ParamMode> = [];
		if (owner is BaseEmitter) {
			var emitter : BaseEmitter = cast owner;
			for (p in emitter.getModeParams())
				for (i in 0...p.def.length)
					modes.push(emitter.getMode(p.name, i));
		}
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
		var modes = new ParticleShaderModes(shader);
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
			editParam(ctx, shader, modes, { name: prop.name, t: t, def: base, kind: Particle, groupName: null }, [Constant, Curve], parent);
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

/** The params of a shader under an emitter: a component is its shader prop (Constant) or a particle curve **/
class ParticleShaderModes implements ParamModes {
	var shader : hrt.prefab.Shader;

	public function new(shader: hrt.prefab.Shader) {
		this.shader = shader;
	}

	public function getMode(name: String, comp: Int) : ParamMode {
		var c = Lambda.find(shader.particleParams, p -> p.name == name)?.comps[comp];
		return c == null ? null : Curve(c.curve);
	}

	public function setMode(name: String, comp: Int, m: ParamMode) {
		var size = EmitterParam.getParamSize(Lambda.find(shader.getShaderDefinition().data.vars, v -> v.name == name));
		var p = Lambda.find(shader.particleParams, p -> p.name == name);
		if (p == null) {
			p = { name: name, comps: [for (_ in 0...size) null] };
			shader.particleParams.push(p);
		}
		p.comps[comp] = switch (m) {
			case Curve(curve): { curve: curve };
			case Constant(k):
				if (size == 1)
					Reflect.setField(shader.props, name, k);
				else {
					var prop : Array<Dynamic> = Reflect.field(shader.props, name);
					if (!Std.isOfType(prop, Array)) {
						prop = [for (j in 0...size) EmitterParam.baseComponent(prop, size, j)];
						Reflect.setField(shader.props, name, prop);
					}
					prop[comp] = k;
				}
				null;
			case null, _: null;
		}
		if (!Lambda.exists(p.comps, c -> c != null))
			shader.particleParams.remove(p);
	}
}

#end
