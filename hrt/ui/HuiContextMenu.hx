package hrt.ui;

#if hui

typedef MenuItem = hide.comp.ContextMenu.MenuItem;

typedef MenuOptions = {
};

class HuiContextMenu extends HuiPopup {
	static var SRC =
		<hui-context-menu>
		</hui-context-menu>

	function new(items: Array<MenuItem>, options: MenuOptions, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		for (item in items) {
			new HuiContextMenuItem(item, this);
		}
	}
}

class HuiContextMenuItem extends HuiElement {
	static var SRC =
		<hui-context-menu-item>
			<hui-element id="icon"></hui-element>
			<hui-element id="content"></hui-element>
			<hui-element id="end-of-line"></hui-element>
		</hui-context-menu-item>

	var contextMenu(get, never): HuiContextMenu;
	var item: MenuItem;

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
	}

	function click(e: hxd.Event) : Void {
		e.cancel = true;
		e.propagate = false;
		if (item.click != null)
			item.click();

		if (!item.stayOpen)
			contextMenu.close();
	}
}

#end