package hrt.ui;

#if hui

/**
	Button that opens a menu for title bars
**/
class HuiButtonMenu extends HuiElement {
	static var SRC =
		<hui-menu>
		</hui-menu>

	var items: Array<hrt.ui.HuiContextMenu.MenuItem>;
	var contextMenu: HuiContextMenu;

	override function new(items: Array<hrt.ui.HuiContextMenu.MenuItem>, ?parent) {
		super(parent);
		initComponent();

		this.items = items;

		onClick = click;
	}
}

#end