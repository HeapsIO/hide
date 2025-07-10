package hide.comp;

class FancyTooltip extends hide.comp.Component {
	var htmlElem : js.html.Element;

	public var x(default, set): Int = 0;
	function set_x(v: Int) {
		x = v;
		htmlElem.style.left = '${x}px';
		return v;
	}

	public var y(default, set): Int = 0;
	function set_y(v: Int) {
		y = v;
		htmlElem.style.top = '${y}px';
		return v;
	}

	public function new(parent: hide.Element = null, el: hide.Element = null) {
		if (parent == null) {
			parent = new hide.Element("body");
		}
		if (el == null) {
			el = new hide.Element("<fancy-tooltip></fancy-tooltip>");
		}
		super(parent, el);
		htmlElem = element.get(0);
		untyped htmlElem.popover = "manual";
	}

	public function show() {
      untyped htmlElem.showPopover();
	}

	public function hide() {
      untyped htmlElem.hidePopover();
	}
}