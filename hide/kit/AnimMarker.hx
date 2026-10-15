package hide.kit;

#if domkit

/** After an animated slider in its line: tells that the field is animated, and if it is keyed at the current time **/
class AnimMarker extends Element {
	/** Adds the animation `menu` to the context menu of `slider`, after its own items **/
	public static function addMenu(slider: Slider<Float>, menu: () -> Array<hrt.ui.HuiMenu.MenuItem>) {
		var own = slider.menuItems;
		slider.menuItems = own == null ? menu : () -> {
			var items = own();
			items.length == 0 ? menu() : items.concat([{ isSeparator: true }]).concat(menu());
		};
	}

	var slider : Slider<Float>;
	var animated : Bool;
	var menu : () -> Array<hrt.ui.HuiMenu.MenuItem>;

	public dynamic function isKeyed() : Bool {
		return false;
	}

	public dynamic function onMarkerClick() : Void {
	}

	public function new(slider: Slider<Float>, animated: Bool, menu: () -> Array<hrt.ui.HuiMenu.MenuItem>) {
		super(null, slider.id + "Anim");
		this.slider = slider;
		this.animated = animated;
		this.menu = menu;
		addMenu(slider, menu);
		var line = Std.downcast(slider.parent, Line);
		if (line == null) {
			line = new Line(null, slider.id + "Line");
			slider.wrapWith(line);
		}
		line.addChildAt(this, line.children.indexOf(slider) + 1);
	}

	/** Follows the current time **/
	override function refreshFields() {
		slider.refreshFields();
		native?.toggleClass("key", isKeyed());
	}

	/** Refreshes the markers under `e` **/
	public static function refreshAll(e: Element) {
		for (c in e.children) {
			if (c is AnimMarker)
				c.refreshFields();
			else
				refreshAll(c);
		}
	}

	override function makeSelf() {
		#if js
		var e = js.Browser.document.createElement("kit-anim-marker");
		e.classList.toggle("animated", animated);
		e.classList.toggle("key", isKeyed());
		e.title = animated ? "Insert or remove a key at the current time (right click: menu)" : "Animate (right click: menu)";
		e.addEventListener("click", (ev: js.html.MouseEvent) -> {
			ev.stopPropagation();
			if (!isDisabled())
				onMarkerClick();
		});
		e.addEventListener("contextmenu", (ev: js.html.MouseEvent) -> {
			ev.preventDefault();
			ev.stopPropagation();
			if (!isDisabled())
				hide.comp.ContextMenu.createFromEvent(ev, menu());
		});
		native = e;
		#else
		super.makeSelf();
		#end
	}
}

#end
