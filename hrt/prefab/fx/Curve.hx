package hrt.prefab.fx;

#if editor
import hide.prefab.EditContext;
import hide.prefab.HideProps;
#end
import hrt.impl.Curve.CurveKey;
import hrt.impl.Curve.CurveKeyMode;
import hrt.prefab.fx.Value;

using Lambda;

enum abstract CurveBlendMode(Int) {
	var None = 0;
	var Blend = 1;
	var RandomBlend = 2;
	var Reference = 3;
}

@:prefabIcon(HuiRes.ui.icons.prefab.curve)
class Curve extends Prefab {
	static var CHANNELS = ["position", "rotation", "scale", "color", "visibility", "localposition", "localrotation"];

	public var maxTime : Float = 5000.;
	public var minValue : Float = 0.;
	public var maxValue : Float = 0.;

	public var datas : Array<hrt.impl.Curve>;
	public var data(get, never) : hrt.impl.Curve;
	function get_data() : hrt.impl.Curve { return datas[0]; }

	public var keys(get, set) : Array<CurveKey>;
	function get_keys() return data.keys;
	function set_keys(v) return data.keys = v;

	public var loop(get, set) : Bool;
	function get_loop() return data.loop;
	function set_loop(v) return data.loop = v;

	public var duration(get, never): Float;
	function get_duration() {
		if (blendMode == Reference)
			return getRef()?.duration ?? 0.0;
		if(keys.length == 0) return 0.0;
		if (blendMode == Blend || blendMode == RandomBlend) {
			var c1:Curve = cast this.children[0];
			var c2:Curve = cast this.children[1];
			return Math.min(c1.duration, c2.duration);
		}
		return data.duration;
	}

	@:s public var blendMode : CurveBlendMode = None;
	@:s public var blendParam : String = null;
	@:s public var remapPath : String = null;
	var refCurve : Curve = null;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
		datas = [new hrt.impl.Curve()];
	}

	public override function load(o:Dynamic) {
		if (o.blendMode != null && !Std.isOfType(o.blendMode, Int)) {
			o.blendMode = Std.parseInt(o.blendMode);
		}
		super.load(o);
		if (o.datas != null) {
			datas = [];
			for (d in (o.datas : Array<Dynamic>)) {
				var c = new hrt.impl.Curve();
				@:privateAccess c.copyFromDynamic(d);
				datas.push(c);
			}
		}
		else
			@:privateAccess data.copyFromDynamic(o);
		if( keys.length == 0 ) {
			addKey(0.0, 0.0);
			addKey(1.0, 1.0);
		}
		name = StringTools.replace(name, ".", ":");
		#if editor
		if (Std.downcast(parent, Curve) != null) {
			if (StringTools.startsWith(name, parent.name)) {
				name = StringTools.replace(name, parent.name + ":", "");
			}
		}
		#else
		if (blendMode == None)
			for (d in datas)
				d.bakeValues();
		#end
	}

	public function findKey(time: Float, tolerance: Float) {
		return data.findKey(time, tolerance);
	}

	public function addKey(time: Float, ?val: Float, ?mode=null) {
		return data.addKey(time, val, mode);
	}

	public function getBounds(bounds: h2d.col.Bounds = null) {
		if (blendMode == Reference)
			return getRef()?.getBounds(bounds) ?? bounds ?? new h2d.col.Bounds();
		return data.getBounds(bounds);
	}

	public function getVal(time: Float) : Float {
		if (blendMode == Reference) {
			throw "getVal shoudln't be called on curves with Reference mode";
		}
		return data.getVal(time);
	}

	public function getSum(time: Float) : Float {
		if (blendMode == Reference)
			return getRef()?.getSum(time) ?? 0.0;
		return data.getSum(time);
	}

	public function sample(numPts: Int) {
		if (blendMode == Reference)
			return getRef()?.sample(numPts) ?? [];
		var vals = data.sample(numPts);
		for (v in vals) {
			if (v < minValue) minValue = v;
			if (v > maxValue) maxValue = v;
		}
		return vals;
	}

	public function getRemapParameter() : Null<String> {
		if (remapPath == null)
			return null;
		var param = StringTools.replace(remapPath, "$param.", "");
		if (param != remapPath)
			return param;
		return null;
	}

	public function isPlain() {
		return blendMode == None && (remapPath == null || remapPath == "");
	}

	public function isParticleCurve() {
		var rootCurve : Prefab = this;
		while (rootCurve.parent is Curve)
			rootCurve = rootCurve.parent;
		var emitter : EmitterParam.ParamOwner = rootCurve.parent is EmitterParam.ParamOwner ? cast rootCurve.parent : null;
		if (emitter == null)
			return rootCurve.findParent(Prefab, p -> p is EmitterParam.ParamOwner) != null;
		return !isChannel(rootCurve.name) && !isParamName(emitter, rootCurve.name);
	}

	public function makeVal() : Value {
		var remap = getRemapParameter();
		inline function fail(what: String) : Value throw '${getAbsPath(true)}: $what is not supported';
		if (remap == null && (remapPath ?? "") != "")
			return fail("a time remap by another curve");
		return switch(blendMode) {
			case None, RandomBlend:
				remap == null ? VCurve(data) : VParamCurve({ c1: data, c2: null, param: remap });
			case Blend:
				var ca = Std.downcast(this.children[0], Curve);
				var cb = Std.downcast(this.children[1], Curve);
				if (remap != null)
					fail("a remapped blend");
				else if ((ca != null && !ca.isPlain()) || (cb != null && !cb.isPlain()))
					fail("a blend of curves that are not plain");
				else if (ca == null && cb == null)
					VConst(0.0);
				else if (ca == null || cb == null || blendParam == null)
					VCurve((ca ?? cb).data);
				else
					VParamCurve({ c1: ca.data, c2: cb.data, param: blendParam });
			case Reference:
				if (remap != null)
					return fail("a remapped reference");
				var ref = getRef();
				switch(ref?.makeVal()) {
					case null: VConst(0.0);
					case v = VConst(_) | VCurve(_) | VParamCurve(_): v;
					case v: fail("a reference to " + v);
				}
			default:
				throw "invalid blendMode value";
		}
	}

	public static function getCurve(parent : Prefab, name: String, onlyEnabled=true) : Curve {
		return hrt.prefab.Curve.findCurve(parent, name, onlyEnabled, c -> c.to(Curve));
	}

	public static function getCurves(parent: Prefab, prefix: String) : Array<Curve> {
		return hrt.prefab.Curve.findCurves(parent, prefix, c -> c.to(Curve));
	}

	public static function getVectorValue(curves: Array<Curve>, defVal: Float=0.0) : Value {
		inline function find(s) {
			return findSuffix(curves, s);
		}
		var x = find(":x");
		var y = find(":y");
		var z = find(":z");
		var w = find(":w");

		inline function curveOrVal(c: Curve, defVal: Float) : Value {
			return c == null ? VConst(defVal) : c.makeVal();
		}

		return VVector(
			curveOrVal(x, defVal),
			curveOrVal(y, defVal),
			curveOrVal(z, defVal),
			curveOrVal(w, 1.0));
	}

	public static function getColorValue(curves: Array<Curve>) : Value {
		inline function find(s) {
			return findSuffix(curves, s);
		}

		var r = find(":r");
		var g = find(":g");
		var b = find(":b");
		var a = find(":a");
		var h = find(":h");
		var s = find(":s");
		var l = find(":l");

		if(h != null || s != null || l != null) {
			return VHsl(
				h != null ? h.makeVal() : VConst(0.0),
				s != null ? s.makeVal() : VConst(1.0),
				l != null ? l.makeVal() : VConst(1.0),
				a != null ? a.makeVal() : VConst(1.0));
		}

		if(a != null && r == null && g == null && b == null)
			return a.makeVal();

		if(a == null && r == null && g == null && b == null)
			return VConst(1.0); // White by default

		return VVector(
			r != null ? r.makeVal() : VConst(1.0),
			g != null ? g.makeVal() : VConst(1.0),
			b != null ? b.makeVal() : VConst(1.0),
			a != null ? a.makeVal() : VConst(1.0));
	}

	override function save() {
		var o = super.save();
		if (datas.length == 1)
			@:privateAccess data.copyToDynamic(o);
		else
			o.datas = [for (d in datas) @:privateAccess d.copyToDynamic(null)];
		return o;
	}

	override function copy(o:Prefab) {
		super.copy(o);
		datas = [];
		for (d in (cast o : Curve).datas) {
			var c = new hrt.impl.Curve();
			@:privateAccess c.copyFromOther(d);
			datas.push(c);
		}
	}

	override function makeInstance() {
		refCurve = null;
	}

	function getRef() : Curve {
		if (refCurve != null)
			return refCurve;
		var root = getRoot(false);
		refCurve = root.locatePrefab(blendParam)?.to(Curve);
		if (refCurve == this) refCurve = null;
		return refCurve;
	}

	function isBlendChild() {
		var p = Std.downcast(parent, Curve);
		return p != null && (p.blendMode == Blend || p.blendMode == RandomBlend);
	}

	override function edit2(ctx: hrt.prefab.EditContext2) {
		super.edit2(ctx);

		ctx.build(
			<root>
				<category("Parameters")>
					<checkbox field={loop}/>
					<select field={blendMode} id="blend-mode-select" if (!isBlendChild() || this.blendMode != CurveBlendMode.None)/>
					<select([{label: "None", value: null}]) field={blendParam} id="blend-param-select" if (this.blendMode == CurveBlendMode.Blend || this.blendMode == CurveBlendMode.Reference)/>
					<select([{label: "None", value: null}]) label="Time Remap" id="remap-select" field={remapPath} if (this.blendMode == CurveBlendMode.None && (!isBlendChild() || this.remapPath != null))/>
					<line label="Curve" if (this.blendMode == CurveBlendMode.None)><curve(name) id="curve-editor"/></line>
				</category>
			</root>
		);

		if (curveEditor != null) {
			curveEditor.maxTime = Math.POSITIVE_INFINITY;
			for (d in datas)
				curveEditor.addTrack(d);
			if (datas.length == 2)
				curveEditor.addBand(curveEditor.tracks[0], curveEditor.tracks[1]);
		}

		if (blendModeSelect != null)
			blendModeSelect.onValueChange = (_) -> {
				ctx.rebuildInspector();
			}

		var root = Std.downcast(getRoot(false), FX);
		if (blendParamSelect != null) {
			var entries = blendMode == Blend ? [for(p in root?.parameters ?? []) { label: p.name, value: p.name }]
				: [for(c in getRoot(false).flatten(Curve)) if (c != this) { label: c.getAbsPath(), value: c.getAbsPath() }];
			entries.insert(0, { label: "None", value: null });
			blendParamSelect.setEntries(entries);
			blendParamSelect.value = blendParam;
			blendParamSelect.onValueChange = (_) -> refCurve = null;
		}
		if (remapSelect != null) {
			var entries = [for(p in root?.parameters ?? []) { label: p.name, value: "$param." + p.name }];
			entries.insert(0, { label: "None", value: null });
			remapSelect.setEntries(entries);
			remapSelect.value = remapPath;
		}
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
		<div class="group" name="Parameters">
			<dl>
				<dt>Loop curve</dt><dd><input type="checkbox" field="loop"/></dd>
				<div id="mode">
					<dt>Blend Mode</dt><dd>
						<select class="blendmode-selector" id="blendMode">
							<option value="0">None</option>
							<option value="1">Blend curve</option>
							<option value="2">Random between two curves</option>
							<option value="3">Curve Reference</option>
						</select>
					</dd>
				</div>
				<div id="parameter">
					<dt>Parameter</dt><dd>
					<select field="blendParam"></select>
					</dd>
				</div>
				<div id="reference">
					<dt>Curve Path</dt><dd>
					<select field="blendParam"></select>
					</dd>
				</div>
				<div id="remap">
					<dt>Time Remap</dt><dd>
						<select field="remapPath"></select>
					</dd>
				</div>
			</dl>
		</div>');

		var blendModeSelect = props.find('#blendMode');

		var refreshBlend = function() {
			var parameter = props.find('#parameter');
			if (blendMode != Blend) {
				parameter.hide();
			}
			else {
				var selecta = parameter.find('[field="blendParam"]');
				parameter.show();
				selecta.empty();
				var root = Std.downcast(getRoot(false), FX);
				if (root != null) {
					for (p in root.parameters) {
						selecta.append(new hide.Element('<option value="${p.name}">${p.name}</option>'));
					}
					selecta.val(blendParam);
				}
			}

			var reference = props.find('#reference');
			if (blendMode != Reference) {
				reference.hide();
			}
			else {
				var selecta = reference.find('[field="blendParam"]');
				reference.show();
				selecta.empty();
				var root = getRoot(false);
				var flat = root.flatten(Curve);
				for (p in flat) {
					if (p == this) continue;
					var path = p.getAbsPath();
					selecta.append(new hide.Element('<option value="${path}">${path}</option>'));
				}
				selecta.val(blendParam);
			}

			props.find('#mode').toggle(!isBlendChild() || blendMode != None);
			var remap = props.find('#remap');
			if (blendMode != None || (isBlendChild() && remapPath == null)) {
				remap.hide();
			}
			else {
				remap.show();
				var select = remap.find('[field=remapPath]');
				select.empty();
				select.append(new hide.Element('<option value="">None</option>'));
				var parameters = Std.downcast(getRoot(false), FX)?.parameters ?? [];
				for (param in parameters) {
					var path = "$param." + param.name;
					select.append(new hide.Element('<option value="${path}">Param: ${param.name}</option>'));
				}
				select.val(remapPath);
			}
		}

		refreshBlend();

		blendModeSelect.val(Std.string(blendMode));
		blendModeSelect.change((_) -> {
			var oldBlend = this.blendMode;
			var oldParam = this.blendParam;
			var newBlend = cast Std.parseInt(blendModeSelect.val());
			var newParam = null;

			function exec(undo : Bool) {
				blendMode = undo ? oldBlend : newBlend;
				blendParam = undo ? oldParam : newParam;
				refreshBlend();
				ctx.onChange(this, "blendMode");
				ctx.rebuildPrefab(this);
			}

			exec(false);
			ctx.properties.undo.change(Custom(exec));
		});

		ctx.properties.add(props, this, function(pname) {
			if (pname == "blendParam") {
				refCurve = null;
				if (containsRefCycle()) {
					hide.Ide.inst.quickMessage("Curve reference create a cycle");
					blendParam = null;
					refCurve = null;
				}
			}
			if (pname == "remapPath") {
				if (remapPath == "")
					remapPath = null;
			}
			refreshBlend();
			@:privateAccess ctx.scene.editor.refreshTree(SceneTree);
			ctx.onChange(this, pname);
		});

		var ce = new hide.comp.Timeline(ctx.properties.undo, ctx.properties.element, false);
		ce.saveDisplayKey = this.getAbsPath(true);
		ce.curves.push(this);
		ce.refresh();
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "Curve", allowParent : isInFX, allowChildren : _ -> false };
	}

	public static function isInFX( p : Prefab ) {
		return p.findParent(FX, null, true) != null || p.findParent(FX2D, null, true) != null;
	}
	#end

	function containsRefCycle(?visited: Map<Curve, Bool>) : Bool {
		if (blendMode != Reference) return false;
		var visited = visited?.copy() ?? [];
		var cur = this;
		while (cur != null) {
			if (visited.get(cur) != null)
			{
				return true;
			}
			visited.set(cur, true);
			if (cur.blendMode == Blend || cur.blendMode == RandomBlend) {
				for (i in 0...2) {
					var subCurve = Std.downcast(cur.children[i], Curve);
					if (subCurve.containsRefCycle(visited)) {
						return true;
					}
				}
			}
			cur = cur.getRef();
		}
		return false;
	}

	static inline function findSuffix(curves: Array<Curve>, suffix: String) {
		return curves.find(c -> StringTools.endsWith(c.name.toLowerCase(), suffix));
	}

	static function isChannel(name: String) {
		return name != null && CHANNELS.contains(name.split(":")[0].toLowerCase());
	}

	static function isParamName(emitter: EmitterParam.ParamOwner, name: String) {
		var base = name?.split(":")[0];
		return Lambda.exists(emitter.getSettings(), p -> p.animate == true && p.name == base) || Lambda.exists(emitter.getModeParams(), p -> p.kind != Particle && p.name == base);
	}

	static var _ = Prefab.register("fxcurve", Curve);
}
