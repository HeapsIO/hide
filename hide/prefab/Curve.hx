package hide.prefab;

typedef CurveHandle = {
	dt: Float,
	dv: Float
}

enum CurveKeyMode {
	Aligned;
	Free;
	Linear;
	Constant;
}

typedef CurveKey = {
	time: Float,
	value: Float,
	?prevHandle: CurveHandle,
	?nextHandle: CurveHandle,
	?mode: CurveKeyMode,
}

typedef CurveKeys = Array<CurveKey>;

class Curve extends Prefab {

	public var duration : Float = 0.;
	public var keys : CurveKeys = [];

   	public function new(?parent) {
		super(parent);
		this.type = "curve";
	}

	override function load(o:Dynamic) {
		duration = o.duration;
		keys = o.keys;
	}

	override function save() {
		return {
			duration: duration,
			keys: keys
		};
	}
}
