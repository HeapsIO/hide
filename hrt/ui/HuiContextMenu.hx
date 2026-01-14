package hrt.ui;

#if hui

typedef MenuItem = hide.comp.ContextMenu.MenuItem;

typedef MenuOptions = {
};

class HuiContextMenu extends HuiPopup {
	var submenu : HuiContextMenu = null;
	var openTimer: haxe.Timer.Timer;
	var itemElements: Array<HuiContextMenuItem> = [];

	@:p var submenuOpenDelaySec : Float = 0.25;

	static var SRC =
		<hui-context-menu>
		</hui-context-menu>

	function new(items: Array<MenuItem>, options: MenuOptions, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		for (item in items) {
			var item = new HuiContextMenuItem(item, this);
			item.onOver = (e) -> {
				trace("item in");
				e.propagate = true;
				openTimer?.stop();
				openTimer = haxe.Timer.delay(onOpenTimer.bind(item), Std.int(submenuOpenDelaySec * 1000));
			}

			item.onOut = (e) -> {
				trace("item out");
				e.propagate = true;
				openTimer?.stop();
				openTimer = haxe.Timer.delay(onOpenTimer.bind(null), Std.int(submenuOpenDelaySec * 1000));
			}
			itemElements.push(item);
		}
	}

	function onOpenTimer(element: HuiContextMenuItem) {
		// we were removed from the scene
		if (this.parent == null)
			return;

		if (submenu != null) {
			submenu.close();
		}

		if (element != null && element.item.menu != null) {
			submenu = new HuiContextMenu(element.item.menu, {});
			var index = parent.children.indexOf(this);
			parent.addChildAt(submenu, index+1);
			submenu.anchor = Element(element);
			submenu.anchorY = StartInside;

			submenu.onOver = (e) -> {
				openTimer?.stop();
				openTimer = null;
				element.dom.hover = true;
				onOver(e);
			}

			submenu.onOut = (e) -> {
				openTimer?.stop();
				openTimer = haxe.Timer.delay(onOpenTimer.bind(null), Std.int(submenuOpenDelaySec * 1000));
				element.dom.hover = false;
				onOut(e);
			}

			submenu.onFinalClose = () -> {
				submenu = null;
				close();
				onFinalClose();
			}
		}
	}

	override function close() {
		submenu?.close();
		submenu = null;
		openTimer?.stop();
		openTimer = null;
		super.close();
	}

	/**When the user clicked a button and we need to close everything down**/
	dynamic function onFinalClose() {
	}
}

@:access(hrt.ui.HuiContextMenu)
class HuiContextMenuItem extends HuiElement {
	static var SRC =
		<hui-context-menu-item>
			<hui-element id="icon"></hui-element>
			<hui-element id="content"></hui-element>
			<hui-element id="end-of-line"></hui-element>
		</hui-context-menu-item>

	var contextMenu(get, never): HuiContextMenu;
	public var item: MenuItem;

	function get_contextMenu() : HuiContextMenu {return Std.downcast(parent, HuiContextMenu);};


	public function new(item: MenuItem, ?parent: h2d.Object) {
		super(parent);
		this.item = item;
		initComponent();

		onClick = click;

		if (item.isSeparator) {
			dom.addClass("separator");
		}

		if (item.icon != null) {
			icon.backgroundType = "hui";
			icon.huiBg.image = {path: item.icon, mode: Fit};
		}

		if (item.label != null) {
			var ftmText = new HuiFmtText(item.label, content);
		}

		if (item.menu != null) {
			endOfLine.backgroundType = "hui";
			endOfLine.huiBg.image = {path: "ui/icons/chevronRight.png", mode: Fit};
		}

		interactive.propagateEvents = true;
	}

	function click(e: hxd.Event) : Void {
		e.cancel = true;
		e.propagate = false;
		if (item.click != null)
			item.click();

		if (!item.stayOpen) {
			contextMenu.close();
			contextMenu.onFinalClose();
		}
	}
}

#end