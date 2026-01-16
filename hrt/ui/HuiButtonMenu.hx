package hrt.ui;

#if hui

/**
	Button that opens a menu for title bars
**/
class HuiButtonMenu extends HuiElement {
	static var SRC =
		<hui-button-menu>
		</hui-button-menu>

	var items: Array<hrt.ui.HuiMenu.MenuItem>;
	var contextMenu: HuiMenu;

	override function new(items: Array<hrt.ui.HuiMenu.MenuItem>, ?parent) {
		super(parent);
		initComponent();

		this.items = items;

		onClick = click;
	}

	function click(e:hxd.Event) {

	}
}

#end