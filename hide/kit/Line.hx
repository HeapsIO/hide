package hide.kit;

#if domkit

class Line extends Element {
	@:attr public var label: String;
	@:attr public var multiline: Bool = false;
	@:attr public var full: Bool = false;


	#if js
	public var labelElement: NativeElement;
	public var multilineElement: NativeElement;
	override function get_nativeContent():NativeElement {
		return multilineElement ?? native;
	}
	#else
	public var labelContainer: hrt.ui.HuiElement;
	public var labelText: hrt.ui.HuiFmtText;
	#end

	override function makeSelf():Void {
		#if js
		if (!full) {
			labelElement = js.Browser.document.createElement("kit-label");

			if (label != null) {
				var span = js.Browser.document.createSpanElement();
				span.innerText = label;
				labelElement.appendChild(span);
			}

			if (!multiline) {
				stealChildLabel(labelElement);
			}
		} else {
			trace("break");
		}

		var me = null;
		if (multiline) {
			me = js.Browser.document.createElement("kit-multiline");
		}

		setupPropLine(labelElement, me, false);

		this.multilineElement = me;
		#else
		native = new hrt.ui.HuiElement();
		native.dom.addClass("line");
		#end
	}
}

#end