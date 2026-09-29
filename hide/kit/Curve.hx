package hide.kit;

#if domkit

class Curve extends Element {
	public var value(default, set) : hrt.prefab.Curve;
	var curveEditor: #if hui hrt.ui.HuiCurveBox #elseif js hide.comp.CurveEditor #else NativeElement #end;

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
		#if js
		var ctx = @:privateAccess (cast root.editor : hide.prefab.EditContext.HideJsEditContext2).ctx;
		var container = new hide.Element('<div class="kit-curve"></div>');

		curveEditor = new hide.comp.CurveEditor(ctx.properties.undo, container, false);
		setupPropLine(null, container[0], false);

		var resizeObserver = new hide.comp.ResizeObserver((_, _) -> refreshCurve());
		resizeObserver.observe(container[0]);
		#elseif hui
		curveEditor = new hrt.ui.HuiCurveBox();
		setupPropLine(null, curveEditor, false);
		refreshCurve();
		#end
	}

	function refreshCurve() {
		#if js
		if (curveEditor != null && value != null && curveEditor.element.width() > 0) {
			curveEditor.saveDisplayKey = value.getAbsPath(true);
			curveEditor.curves = [value];
			curveEditor.refresh();
		}
		#elseif hui
		if (curveEditor != null)
			curveEditor.value = value;
		#end
	}
}

#end