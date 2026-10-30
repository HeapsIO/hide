package hrt.prefab;

#if editor
import hide.prefab.EditContext;
import hide.prefab.HideProps;
#end

import hrt.impl.Curve.CurveKey;
import hrt.impl.Curve.CurveKeyMode;

using Lambda;

@:prefabIcon(HuiRes.ui.icons.prefab.curve)
class Curve extends Prefab {
	@:isVar public var data(get, null) = new hrt.impl.Curve();
	function get_data() { return data; }

	public var keys(get, set) : Array<CurveKey>;
	function get_keys() return data.keys;
	function set_keys(v) return data.keys = v;

	public var loop(get, set) : Bool;
	function get_loop() return data.loop;
	function set_loop(v) return data.loop = v;

	public var duration(get, never): Float;
	function get_duration() return data.duration;

	public var maxTime : Float = 5000.;
	public var minValue : Float = 0.;
	public var maxValue : Float = 0.;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
	}

	public override function load(o:Dynamic) {
		super.load(o);
		@:privateAccess data.copyFromDynamic(o);
		if( keys.length == 0 ) {
			addKey(0.0, 0.0);
			addKey(1.0, 1.0);
		}
		name = StringTools.replace(name, ".", ":");
		#if !editor
		bakeValues();
		#end
	}

	public function findKey(time: Float, tolerance: Float) {
		return data.findKey(time, tolerance);
	}

	public function addKey(time: Float, ?val: Float, ?mode=null) {
		return data.addKey(time, val, mode);
	}

	public function getBounds(bounds: h2d.col.Bounds = null) {
		return data.getBounds(bounds);
	}

	public function getVal(time: Float) : Float {
		return data.getVal(time);
	}

	public function getSum(time: Float) : Float {
		return data.getSum(time);
	}

	public function sample(numPts: Int) {
		var vals = data.sample(numPts);
		for (v in vals) {
			if (v < minValue) minValue = v;
			if (v > maxValue) maxValue = v;
		}
		return vals;
	}

	#if editor
	// Returns the visual representation of this curve as an svg path `d` data
	public function getSvgString() : String {
		var data = "";
		var bounds = this.getBounds();
		if (this.keys.length > 0) {
			data += 'M ${bounds.xMin} ${this.keys[0].value} H ${this.keys[0].time}';

			for (i in 1...this.keys.length) {
				data += ' ';
				var prev = this.keys[i-1];
				var next = this.keys[i];
				switch (prev.mode) {
					case Constant:
						data += 'H ${next.time} V ${next.value}';
					case Aligned, Free, Linear:
						{
							var prevDt = prev.nextHandle?.dt ?? 0.0;
							var prevDv = prev.nextHandle?.dv ?? 0.0;
							var nextDt = next.prevHandle?.dt ?? 0.0;
							var nextDv = next.prevHandle?.dv ?? 0.0;

							var c0 = prev.time;
							var c1 = prev.time + prevDt;
							var c2 = next.time + nextDt;
							var c3 = next.time;

							// solve bezier(c0,c1,c2,c2, x) = bezier(c0,c1,c2,c2, 0.5) for x
							final sqrt3 = hxd.Math.sqrt(3);
							var r0: Float;
							var r1: Float;

							var midt = hrt.impl.Curve.bezier(c0,c1,c2,c3, 0.5);
							if (midt < c0) {
								// solve bezier(c0,c1,c2,c2, x) = c0 for x;
								var div = 2*c3-6*c2+6*c1-2*c0;
								var fact = sqrt3*hxd.Math.sqrt((4*c0-4*c1)*c3+3*c2*c2-6*c0*c2+4*c0*c1-c0*c0);
								r0 = -(fact+3*c2-6*c1+3*c0)/div;
								r1 = (fact-3*c2+6*c1-3*c0)/div;
							}
							else if (midt > c3) {
								// solve bezier(c0,c1,c2,c2, x) = c3 for x;
								var div = 2*c3-6*c2+6*c1-2*c0;
								var fact = sqrt3*hxd.Math.sqrt(-c3*c3+(4*c2-6*c1+4*c0)*c3-4*c0*c2+3*c1*c1);
								r0 = -((fact+c3-3*c1+2*c0)/(div));
								r1 = (fact-c3+3*c1-2*c0)/(div);
							}
							else {
								// solve bezier(c0,c1,c2,c2, x) = 0.5 for x;
								r0 = -((sqrt3*hxd.Math.sqrt(-c3*c3+(2*c2-14*c1+14*c0)*c3+15*c2*c2+(-(18*c1)-14*c0)*c2+15*c1*c1+2*c0*c1-c0*c0)+c3+3*c2-9*c1+5*c0)/(4*c3-12*c2+12*c1-4*c0));
								r1 = (sqrt3*hxd.Math.sqrt(-c3*c3+(2*c2-14*c1+14*c0)*c3+15*c2*c2+(-(18*c1)-14*c0)*c2+15*c1*c1+2*c0*c1-c0*c0)-c3-3*c2+9*c1-5*c0)/(4*c3-12*c2+12*c1-4*c0);
							}

							if (r0 > r1) {
								var tmp = r1;
								r1 = r0;
								r0 = tmp;
							}

							if (r1 > 1.0) {
								r1 = r0;
								r0 = 0.0;
							}
							if (r0 < 0.0) {
								r0 = r1;
								r1 = 1.0;
							}

							inline function check(a) {
								return (Math.isNaN(a) || a < 0 || a > 1);
							}

							if (check(r0) && check(r1)) {
								data += 'C ${prev.time + prevDt} ${prev.value + prevDv}, ${next.time + nextDt} ${next.value + nextDv}, ${next.time} ${next.value}';
							}
							else {

								if (hxd.Math.isNaN(r0)) {
									r0 = 0.0;
								}
								if (hxd.Math.isNaN(r1)) {
									r1 = 1.0;
								}

								r0 = hxd.Math.clamp(r0, 0.0, 1.0);

								r1 = hxd.Math.clamp(r1, 0.0, 1.0);

								inline function b(t) {
									hrt.impl.Curve.bezier(c0,c1,c2,c3, t);
								}

								// split the curve in two if its loops on itself
								inline function sample(c0 : Float, c1: Float, c2: Float, c3:Float, t: Float) : {startHandle: Float, value: Float, inValue: Float, outValue: Float, endHandle: Float} {

									var a = c0 + (c1-c0) * t;
									var b = c1 + (c2-c1) * t;
									var c = c2 + (c3-c2) * t;
									var d = a + (b-a) * t;
									var e = b + (c-b) * t;
									var x = d + (e-d) * t;

									return {startHandle: a, value:x, inValue: d, outValue: e, endHandle: c};
								}

								var p0x = sample(c0, c1, c2, c3, r0);
								var p1x = sample(c0, c1, c2, c3, r1);

								var p0y = sample(prev.value, prev.value+prevDv, next.value + nextDv, next.value, r0);
								var p1y = sample(prev.value, prev.value+prevDv, next.value + nextDv, next.value, r1);

								if (r0 > 0.0) {
									data += 'C ${p0x.startHandle} ${p0y.startHandle}, ${p0x.inValue} ${p0y.inValue}, ${p0x.value} ${p0y.value} ';
								}

								data += 'L ${hxd.Math.clamp(p1x.value, prev.time, next.time)} ${p1y.value}';

								if (r1 < 1.0) {
									data += ' C ${p1x.outValue} ${p1y.outValue}, ${p1x.endHandle} ${p1y.endHandle}, ${next.time} ${next.value}';
								}
							}
						}
				}
			}
		}
		return data;
	}
	#end

	public static function getCurve(parent : Prefab, name: String, onlyEnabled=true) : Curve {
		return findCurve(parent, name, onlyEnabled, c -> c.to(Curve));
	}

	public static function getCurves(parent: Prefab, prefix: String) : Array<Curve> {
		return findCurves(parent, prefix, c -> c.to(Curve));
	}

	public static function findCurve<T>(parent : Prefab, name: String, onlyEnabled: Bool, get: Prefab -> Null<T>) : T {
		for(c in parent.children) {
			if(onlyEnabled && !c.enabled) continue;
			#if editor
			if (parent.shared.editor?.isHidden(c)) continue;
			#end
			if(!checkName(c.name, name)) continue;
			var curve = get(c);
			if(curve == null) continue;
			return curve;
		}
		return null;
	}

	public static function findCurves<T>(parent: Prefab, prefix: String, get: Prefab -> Null<T>) : Array<T> {
		var ret : Array<T> = null;
		for(c in parent.children) {
			if(!c.enabled) continue;
			#if editor
			if (parent.shared.editor?.isHidden(c)) continue;
			#end
			var idx = c.name.indexOf(":");
			var curvePrefix = (idx >= 0) ? c.name.substr(0, idx) : c.name;
			if(!checkName(curvePrefix, prefix))
				continue;
			var curve = get(c);
			if(curve == null) continue;
			if (ret == null) ret = [];
			ret.push(curve);
		}
		return ret;
	}

	public static function getGroups(curves: Array<Curve>) {
		var groups : Array<{name: String, items: Array<Curve>}> = [];
		for(c in curves) {
			var prefix = c.name.split(":")[0];
			var g = groups.find(g -> g.name == prefix);
			if(g == null) {
				groups.push({
					name: prefix,
					items: [c]
				});
			}
			else {
				g.items.push(c);
			}
		}
		return groups;
	}

	#if castle
	public function initFromCDB(c: cdb.Types.Curve) {
		data.initFromCDB(c);
	}

	public function toCDB() : cdb.Types.Curve {
		return data.toCDB();
	}
	#end

	#if !editor
	function bakeValues() {
		data.bakeValues();
	}
	#end

	override function save() {
		var o = super.save();
		@:privateAccess data.copyToDynamic(o);
		return o;
	}

	override function copy(o:Prefab) {
		super.copy(o);
		@:privateAccess data.copyFromOther((cast o : Curve).data);
	}

	override function edit2(ctx: hrt.prefab.EditContext2) {
		super.edit2(ctx);

		ctx.build(
			<root>
				<category("Parameters")>
					<checkbox field={loop}/>
					<line label="Curve"><curve(name) id="curve-editor"/></line>
				</category>
			</root>
		);

		if (curveEditor != null) {
			curveEditor.maxTime = Math.POSITIVE_INFINITY;
			curveEditor.addTrack(data);
		}
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
		<div class="group" name="Parameters">
			<dl>
				<dt>Loop curve</dt><dd><input type="checkbox" field="loop"/></dd>
			</dl>
		</div>');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});

		var ce = new hide.comp.Timeline(ctx.properties.undo, ctx.properties.element, false);
		ce.saveDisplayKey = this.getAbsPath(true);
		ce.curves.push(this);
		ce.refresh();
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "Curve", allowParent : p -> !hrt.prefab.fx.Curve.isInFX(p), allowChildren : _ -> false };
	}
	#end

	static inline function checkName(a: String, b: String) {
		return a == b || a.toLowerCase() == b.toLowerCase();
	}

	static var _ = Prefab.register("curve", Curve);
}
