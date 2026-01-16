package hrt.ui;

#if hui

/**
	Button that opens a menu for title bars
**/
class HuiButtonMenu extends HuiElement {
	static var SRC =
		<hui-button-menu>
		</hui-button-menu>

	var getItems: Void -> Array<hrt.ui.HuiMenu.MenuItem>;
	var menu: HuiMenu;

	override function new(getItems: Void -> Array<hrt.ui.HuiMenu.MenuItem>, ?parent) {
		super(parent);
		initComponent();

		this.getItems = getItems;

		onClick = click;
		onOver = over;
	}

	function click(e:hxd.Event) {
		open();
	}

	function open() {
		menu = uiBase.openMenu(getItems(), {}, {object: Element(this), directionX: StartInside, directionY: EndOutside});
		menu.onCloseListeners.push(onClose);
		dom.addClass("open");
	}

	function onClose() {
		menu = null;
		dom.removeClass("open");
	}

	function over(e: hxd.Event) {
		// See of another buttonMenu is open, if that the case, close it and open ours instead
		for (sibling in parent.children) {
			var otherButtonMenu = Std.downcast(sibling, HuiButtonMenu);
			if (otherButtonMenu == null || otherButtonMenu == this)
				continue;
			if (otherButtonMenu.menu == null)
				continue;
			otherButtonMenu.menu.close();
			open();
			break;
		}
	}
}

#end