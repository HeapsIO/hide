package hrt.prefab.fx;

#if editor
import hide.prefab.EditContext;
import hide.prefab.HideProps;
#end
import hrt.prefab.fx.Value;

using Lambda;

enum CurveBlendMode {
	/** One data, read at the time or at the FX parameter `param` **/
	None;
	/** Two datas, blended by the FX parameter `param` **/
	Blend;
	/** Two datas, a random between them: the Curve Range of the emitter params **/
	Range;
	/** The curve at `refPath` **/
	Reference;
}

@:prefabIcon(HuiRes.ui.icons.prefab.curve)
class Curve extends hrt.prefab.Curve {
	static var CHANNELS = ["position", "rotation", "scale", "color", "visibility", "localposition", "localrotation"];

	public var datas : Array<hrt.impl.Curve>;
	override function get_data() : hrt.impl.Curve { return datas[0]; }

	override function get_duration() {
		if (blendMode == Reference)
			return getRef()?.duration ?? 0.0;
		if (blendMode == Blend)
			return Math.min(datas[0].duration, datas[1].duration);
		return data.duration;
	}

	@:s public var blendMode : CurveBlendMode = None;
	@:s public var param : String;
	@:s public var refPath : String;
	var refCurve : Curve = null;

	override function initData() {
		datas = [new hrt.impl.Curve()];
	}

	override function loadData(o:Dynamic) {
		if (o.datas == null) {
			super.loadData(o);
			return;
		}
		datas = [];
		for (d in (o.datas : Array<Dynamic>)) {
			var c = new hrt.impl.Curve();
			@:privateAccess c.copyFromDynamic(d);
			datas.push(c);
		}
	}

	override function saveData(o:Dynamic) {
		// a reference reads the keys of its curve
		if (blendMode == Reference)
			return;
		if (datas.length == 1)
			super.saveData(o);
		else
			o.datas = [for (d in datas) @:privateAccess d.copyToDynamic(null)];
	}

	#if !editor
	override function bakeValues() {
		if (blendMode != Reference)
			for (d in datas)
				d.bakeValues();
	}
	#end

	override function getBounds(bounds: h2d.col.Bounds = null) {
		if (blendMode == Reference)
			return getRef()?.getBounds(bounds) ?? bounds ?? new h2d.col.Bounds();
		return data.getBounds(bounds);
	}

	override function getVal(time: Float) : Float {
		if (blendMode == Reference) {
			throw "getVal shoudln't be called on curves with Reference mode";
		}
		return data.getVal(time);
	}

	override function getSum(time: Float) : Float {
		if (blendMode == Reference)
			return getRef()?.getSum(time) ?? 0.0;
		return data.getSum(time);
	}

	override function sample(numPts: Int) {
		if (blendMode == Reference)
			return getRef()?.sample(numPts) ?? [];
		return data.sample(numPts);
	}

	public function isPlain() {
		return blendMode == None && param == null;
	}

	public function isParticleCurve() {
		var rootCurve : Prefab = this;
		while (rootCurve.parent is Curve)
			rootCurve = rootCurve.parent;
		var parent = rootCurve.parent;
		if (!EmitterHelper.isEmitter(parent))
			return rootCurve.findParent(Prefab, p -> EmitterHelper.isEmitter(p)) != null;
		return !isChannel(rootCurve.name) && !isParamName(parent, rootCurve.name);
	}

	override function makeVal() : Value {
		inline function fail(what: String) : Value throw '${getAbsPath(true)}: $what is not supported';
		return switch(blendMode) {
			case None:
				param == null ? VCurve(data) : VParamCurve({ c1: data, c2: null, param: param });
			case Blend:
				VParamCurve({ c1: datas[0], c2: datas[1], param: param });
			case Range:
				fail("a random range out of the Curve Range of the emitter params");
			case Reference:
				var ref = getRef();
				switch(ref?.makeVal()) {
					case null: VConst(0.0);
					case v = VConst(_) | VCurve(_) | VParamCurve(_): v;
					case v: fail("a reference to " + v);
				}
		}
	}

	public static function getCurve(parent : Prefab, name: String, onlyEnabled=true) : Curve {
		return hrt.prefab.Curve.findCurve(parent, name, onlyEnabled, c -> c.to(Curve));
	}

	public static function getCurves(parent: Prefab, prefix: String) : Array<Curve> {
		return hrt.prefab.Curve.findCurves(parent, prefix, c -> c.to(Curve));
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
		refCurve = root.locatePrefab(refPath)?.to(Curve);
		if (refCurve == this) refCurve = null;
		return refCurve;
	}

	/** Two datas for a blend or a range, one else (the second one starts as a copy of the first) **/
	public function syncDatas() {
		var two = blendMode == Blend || blendMode == Range;
		if (two && datas.length < 2) {
			var d = new hrt.impl.Curve();
			@:privateAccess d.copyFromOther(datas[0]);
			datas.push(d);
		} else if (!two && datas.length > 1)
			datas.resize(1);
	}

	override function edit2(ctx: hrt.prefab.EditContext2) {
		// not super: replaces the inspector of a plain curve
		ctx.build(
			<root>
				<category("Parameters")>
					<checkbox field={loop}/>
					<select field={blendMode} id="blend-mode-select"/>
					<select([{label: "None", value: null}]) label="Blend Param" field={param} id="blend-param-select" if (this.blendMode == CurveBlendMode.Blend)/>
					<select([{label: "None", value: null}]) label="Reference" field={refPath} id="ref-select" if (this.blendMode == CurveBlendMode.Reference)/>
					<select([{label: "None", value: null}]) label="Time Remap" id="remap-select" field={param} if (this.blendMode == CurveBlendMode.None)/>
					<line label="Curve" if (this.blendMode != CurveBlendMode.Reference)><curve(name) id="curve-editor"/></line>
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
				syncDatas();
				ctx.rebuildInspector();
			}

		var root = Std.downcast(getRoot(false), FX);
		var paramEntries : Array<hide.kit.Select.SelectEntry> = [for(p in root?.parameters ?? []) { label: p.name, value: p.name }];
		paramEntries.insert(0, { label: "None", value: null });
		if (blendParamSelect != null) {
			blendParamSelect.setEntries(paramEntries);
			blendParamSelect.value = param;
		}
		if (refSelect != null) {
			var entries : Array<hide.kit.Select.SelectEntry> = [for(c in getRoot(false).flatten(Curve)) if (c != this) { label: c.getAbsPath(), value: c.getAbsPath() }];
			entries.insert(0, { label: "None", value: null });
			refSelect.setEntries(entries);
			refSelect.value = refPath;
			refSelect.onValueChange = (_) -> refCurve = null;
		}
		if (remapSelect != null) {
			remapSelect.setEntries(paramEntries);
			remapSelect.value = param;
		}
	}

	#if editor
	override function edit( ctx : EditContext ) {
		// not super: replaces the inspector of a plain curve
		var props = new hide.Element('
		<div class="group" name="Parameters">
			<dl>
				<dt>Loop curve</dt><dd><input type="checkbox" field="loop"/></dd>
				<div id="mode">
					<dt>Blend Mode</dt><dd>
						<select class="blendmode-selector" id="blendMode">
							<option value="None">None</option>
							<option value="Blend">Blend curve</option>
							<option value="Reference">Curve Reference</option>
						</select>
					</dd>
				</div>
				<div id="parameter">
					<dt>Parameter</dt><dd>
					<select field="param"></select>
					</dd>
				</div>
				<div id="reference">
					<dt>Curve Path</dt><dd>
					<select field="refPath"></select>
					</dd>
				</div>
				<div id="remap">
					<dt>Time Remap</dt><dd>
						<select field="param"></select>
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
				var selecta = parameter.find('[field="param"]');
				parameter.show();
				selecta.empty();
				var root = Std.downcast(getRoot(false), FX);
				if (root != null) {
					for (p in root.parameters) {
						selecta.append(new hide.Element('<option value="${p.name}">${p.name}</option>'));
					}
					selecta.val(param);
				}
			}

			var reference = props.find('#reference');
			if (blendMode != Reference) {
				reference.hide();
			}
			else {
				var selecta = reference.find('[field="refPath"]');
				reference.show();
				selecta.empty();
				var root = getRoot(false);
				var flat = root.flatten(Curve);
				for (p in flat) {
					if (p == this) continue;
					var path = p.getAbsPath();
					selecta.append(new hide.Element('<option value="${path}">${path}</option>'));
				}
				selecta.val(refPath);
			}

			var remap = props.find('#remap');
			if (blendMode != None) {
				remap.hide();
			}
			else {
				remap.show();
				var select = remap.find('[field=param]');
				select.empty();
				select.append(new hide.Element('<option value="">None</option>'));
				var parameters = Std.downcast(getRoot(false), FX)?.parameters ?? [];
				for (p in parameters) {
					select.append(new hide.Element('<option value="${p.name}">Param: ${p.name}</option>'));
				}
				select.val(param);
			}
		}

		refreshBlend();

		blendModeSelect.val(blendMode.getName());
		blendModeSelect.change((_) -> {
			var oldBlend = this.blendMode;
			var oldParam = this.param;
			var oldRef = this.refPath;
			var newBlend = CurveBlendMode.createByName(blendModeSelect.val());

			function exec(undo : Bool) {
				blendMode = undo ? oldBlend : newBlend;
				param = undo ? oldParam : null;
				refPath = undo ? oldRef : null;
				syncDatas();
				refreshBlend();
				ctx.onChange(this, "blendMode");
				ctx.rebuildPrefab(this);
			}

			exec(false);
			ctx.properties.undo.change(Custom(exec));
		});

		ctx.properties.add(props, this, function(pname) {
			if (pname == "refPath") {
				refCurve = null;
				if (containsRefCycle()) {
					hide.Ide.inst.quickMessage("Curve reference create a cycle");
					refPath = null;
					refCurve = null;
				}
			}
			if (pname == "param") {
				if (param == "")
					param = null;
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
		return { icon : "paint-brush", name : "Curve", allowParent : FX.inFX, allowChildren : _ -> false };
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
			cur = cur.getRef();
		}
		return false;
	}

	static function isChannel(name: String) {
		return name != null && CHANNELS.contains(name.split(":")[0].toLowerCase());
	}

	static function isParamName(emitter: Prefab, name: String) {
		var base = name?.split(":")[0];
		return Lambda.exists(EmitterHelper.getProperties(emitter), p -> p.animate == true && p.name == base) || Lambda.exists(EmitterHelper.getParams(emitter), p -> p.kind != Particle && p.name == base);
	}

	static var _ = Prefab.register("fxcurve", Curve);
}
