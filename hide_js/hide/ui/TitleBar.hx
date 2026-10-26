package hide.ui;

/**
	Title bar of a window created with `customTitleBar` : menu bar and title, the native buttons are drawn on its right.
**/
class TitleBar {

	var menuBar : js.html.Element;
	var title : js.html.Element;
	var current : hide.comp.ContextMenu;
	var currentButton : js.html.Element;

	public function new( window : electron.Window ) {
		var doc = js.Browser.document;
		var element = doc.createDivElement();
		element.classList.add("title-bar");

		var icon = doc.createImageElement();
		icon.classList.add("icon");
		icon.src = "res/" + (hide.Ide.inst.isCDB ? "cdb" : "hide") + ".png";
		element.appendChild(icon);

		menuBar = doc.createDivElement();
		menuBar.classList.add("menu-bar");
		element.appendChild(menuBar);

		title = doc.createDivElement();
		title.classList.add("title");
		element.appendChild(title);

		doc.body.prepend(element);

		// the native buttons only take #rrggbb colors
		function toHex( color : String ) {
			var ctx = doc.createCanvasElement().getContext2d();
			ctx.fillStyle = color;
			ctx.fillRect(0, 0, 1, 1);
			var d = ctx.getImageData(0, 0, 1, 1).data;
			return "#" + StringTools.hex(d[0], 2) + StringTools.hex(d[1], 2) + StringTools.hex(d[2], 2);
		}
		var style = js.Browser.window.getComputedStyle(element);
		window.setTitleBarOverlay(toHex(style.backgroundColor), toHex(style.color));
	}

	public function setTitle( text : String ) {
		title.textContent = text;
	}

	public function setMenu( menu : electron.Menu ) {
		current?.close();
		menuBar.innerHTML = "";

		for( item in menu.items ) {
			var button = js.Browser.document.createDivElement();
			button.classList.add("menu");
			button.textContent = item.label;
			menuBar.appendChild(button);

			// the dropdown is closed by the pointer down outside of it, before the click
			var wasOpen = false;
			button.addEventListener("pointerdown", (_) -> wasOpen = currentButton == button);
			button.addEventListener("click", (_) -> if( !wasOpen ) open(button, item));
			button.addEventListener("mouseenter", (_) -> if( current != null && currentButton != button ) open(button, item));
		}
	}

	function open( button : js.html.Element, item : electron.MenuItem ) {
		current?.close();
		if( item.submenu == null ) {
			item.click();
			return;
		}

		function convert( menu : electron.Menu ) : Array<hrt.ui.HuiMenu.MenuItem> {
			var items : Array<hrt.ui.HuiMenu.MenuItem> = [];
			for( i in menu.items ) {
				if( i.type == Separator ) {
					items.push({ isSeparator : true });
					continue;
				}
				items.push({
					label : i.label,
					enabled : i.enabled,
					checked : i.type == Checkbox ? i.checked : null,
					keys : @:privateAccess i.accelerator,
					menu : i.submenu == null ? null : convert(i.submenu),
					click : i.submenu == null ? () -> i.click() : null,
				});
			}
			return items;
		}

		var menu = hide.comp.ContextMenu.createDropdown(button, convert(item.submenu));
		menu.onClose = function() {
			if( current != menu )
				return;
			button.classList.remove("open");
			current = null;
			currentButton = null;
		};
		button.classList.add("open");
		current = menu;
		currentButton = button;
	}

}
