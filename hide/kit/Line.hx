package hide.kit;

#if domkit

class Line extends Element {
	@:attr public var label: String;
	@:attr public var multiline: Bool = false;
	@:attr public var full: Bool = false;

	var decorationsLeft: Array<Element> = null;

	#if js
	public var labelElement: NativeElement;
	public var multilineElement: NativeElement;
	override function get_nativeContent():NativeElement {
		return multilineElement ?? native;
	}
	#elseif hui
	public var labelContainer: hrt.ui.HuiElement;
	public var labelText: hrt.ui.HuiText;
	#end

	override function makeSelf():Void {
		#if js
		if (!full) {
			labelElement = js.Browser.document.createElement("kit-label");

			if (decorationsLeft != null) {
				for (deco in decorationsLeft) {
					deco.make(false);
					labelElement.appendChild(deco.native);
					deco.native.classList.add("deco-left");
				}

				labelElement.appendChild(js.Browser.document.createElement("kit-push"));
			}

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
		#elseif hui
		native = new hrt.ui.HuiElement();
		native.dom.addClass("line");
		#end
	}

	/**Add a widget to the line that appears at the left edge of the property panel **/
	public function addDecorationLeft(element: Element) : Void {
		decorationsLeft ??= [];
		decorationsLeft.push(element);
		element.parent = this;
		element.root = this.root;
	}
}

#end