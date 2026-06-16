package hide.kit;

#if domkit

class Curve extends Element {
	public var value(default, set) : hrt.prefab.Curve;
	var curveEditor: #if hui hrt.ui.HuiCurveBox #else NativeElement #end;

	function set_value(v: hrt.prefab.Curve) : hrt.prefab.Curve {
		value = v;
		refreshCurve();
		return value;
	}

	public function new(parent: Element, id: String, value: hrt.prefab.Curve) : Void {
		super(parent, id);
		this.value = value;
	}

	override function makeSelf() : Void {
		#if hui
		curveEditor = new hrt.ui.HuiCurveBox();
		setupPropLine(null, curveEditor, false);
		refreshCurve();
		#end
	}

	function refreshCurve() {
		#if hui
		if (curveEditor != null)
			curveEditor.value = value;
		#end
	}
}

#end