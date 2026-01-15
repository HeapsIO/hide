package hrt.ui;

#if hui

typedef MenuItem = hide.comp.ContextMenu.MenuItem;

typedef MenuOptions = {
};

class HuiContextMenu extends HuiPopup {
	var parentMenu: HuiContextMenu = null;
	var submenu : HuiContextMenu = null;
	var openTimer: haxe.Timer.Timer;
	var itemElements: Array<HuiContextMenuItem> = [];
	var selectableElements: Array<HuiContextMenuItem> = [];
	var items: Array<MenuItem>;

	var keyboardFocused(default, set): Int = -1;
	function set_keyboardFocused(v: Int) : Int {
			selectableElements[keyboardFocused]?.dom.removeClass("keyboard-focused");
			keyboardFocused = v;
			var item = selectableElements[keyboardFocused];
			if (item != null) {
				itemsContainer.scrollIntoView(item);
				item.dom.addClass("keyboard-focused");
			}
			return keyboardFocused;
	}

	@:p var submenuOpenDelaySec : Float = 0.25;

	static var SRC =
		<hui-context-menu>
			<hui-input-box id="searchBar"/>
			<hui-element id="itemsContainer"/>
		</hui-context-menu>

	function new(items: Array<MenuItem>, options: MenuOptions, ?parentMenu: HuiContextMenu, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.parentMenu = parentMenu;
		this.items = items;

		searchBar.visible = false;

		itemsContainer.makeInteractive();
		itemsContainer.interactive.propagateEvents = true;

		if (parentMenu == null) {
			onKeyUp = keyUp;
			onTextInput = textInput;
			onKeyDown = keyDownHandler.bind(false);

			searchBar.onKeyDown = keyDownHandler.bind(true);
			searchBar.onChange = () -> {
				keyboardFocused = 0;
				regenerateElements();
			}
			searchBar.onFocusLost = (e) -> {
				searchBar.visible = false;
				regenerateElements();
			}
		}

		regenerateElements();
	}

	function regenerateElements() {
		var filteredList = items;
		if (searchBar.visible) {
			var query = hide.Search.createSearchQuery(searchBar.text);
			if (minWidth == null) {
				minWidth = Std.int(calculatedWidth);
				maxHeight = Std.int(calculatedHeight);
			}

			function rec(items: Array<MenuItem>) : Array<MenuItem> {
				var filteredList = [];

				for (item in items) {
					if (item.menu != null || item.isSeparator) {
						continue;
					}

					if (searchBar.text.length == 0) {
						filteredList.push(item);
						continue;
					}

					var ranges = hide.Search.computeSearchRanges(item.label, query, false);
					if (ranges != null) {
						filteredList.push(item);
					}
				}
				for (item in items) {
					if (item.menu != null) {
						// Avoid infinite loop in the debug contextMenu recursive example
						if (item.menu == items)
							continue;

						var menuFilter = rec(item.menu);
						if (menuFilter.length > 0) {
							filteredList.push({isSeparator: true, label: item.label});
							filteredList = filteredList.concat(menuFilter);
						}
					}
				}

				return filteredList;
			}

			filteredList = rec(items);
		}

		itemsContainer.removeChildren();
		itemElements.resize(0);
		selectableElements.resize(0);

		if (submenu != null)
			submenu.close();

		for (item in filteredList) {
			var itemElement = new HuiContextMenuItem(item, itemsContainer);
			itemElement.onOver = (e) -> {
				e.propagate = true;
				openTimer?.stop();
				openTimer = haxe.Timer.delay(openSubmenu.bind(itemElement), Std.int(submenuOpenDelaySec * 1000));
			}

			itemElement.onOut = (e) -> {
				e.propagate = true;
				openTimer?.stop();
				openTimer = haxe.Timer.delay(openSubmenu.bind(null), Std.int(submenuOpenDelaySec * 1000));
			}
			itemElements.push(itemElement);
			if (!item.isSeparator) {
				selectableElements.push(itemElement);
			}
		}

		if (keyboardFocused >= 0) {
			keyboardFocused = hxd.Math.iclamp(keyboardFocused, 0, selectableElements.length-1);
		}
	}

	function openSubmenu(element: HuiContextMenuItem) {
		// we were removed from the scene
		if (this.parent == null)
			return;

		openTimer?.stop();
		openTimer = null;

		if (submenu != null) {
			submenu.close();
		}

		if (element != null && element.item.menu != null) {
			submenu = new HuiContextMenu(element.item.menu, {}, this);
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
				openTimer = haxe.Timer.delay(openSubmenu.bind(null), Std.int(submenuOpenDelaySec * 1000));
				element.dom.hover = false;
				onOut(e);
			}

			submenu.onFinalClose = () -> {
				submenu = null;
				close();
				onFinalClose();
			}

			submenu.onClose = () -> {
				submenu = null;
			}
		}
	}

	function closeTopmostMenu() {
		if (submenu != null) {
			submenu.closeTopmostMenu();
		}
		close();
	}

	function keyDownHandler(isSearchBar: Bool, e: hxd.Event) {
		// we need to do this because e.cancel = true will make the event propagate even
		// if e.propagate is false, and we need the e.cancel = true to override the search bar
		// default behavior
		if (!isSearchBar && searchBar.textInput.hasFocus())
			return;

		if (e.keyCode == hxd.Key.ESCAPE && !searchBar.visible) {
			if (submenu != null && submenu.keyboardFocused >= 0) {
				submenu.keyDownHandler(isSearchBar, e);
				return;
			}
			close();
			return;
		}

		if (e.keyCode == hxd.Key.ENTER && keyboardFocused >= 0) {
			if (submenu != null && submenu.keyboardFocused >= 0) {
				submenu.keyDownHandler(isSearchBar, e);
				return;
			}
			selectableElements[keyboardFocused].validate();
			e.cancel = isSearchBar; // cancel default behavior for the search bar
			e.propagate = false;
			return;
		}

		if (e.keyCode == hxd.Key.LEFT && !searchBar.visible) {
			if (submenu != null && submenu.keyboardFocused >= 0) {
				submenu.keyDownHandler(isSearchBar, e);
				return;
			}
			if (parentMenu != null) {
				close();
				e.propagate = false;
			}
			return;
		}

		if (e.keyCode == hxd.Key.RIGHT && !searchBar.visible) {
			if (submenu != null && submenu.keyboardFocused >= 0) {
				submenu.keyDownHandler(isSearchBar, e);
				return;
			}
			if (selectableElements[keyboardFocused]?.item.menu != null) {
				openSubmenu(selectableElements[keyboardFocused]);
				submenu.keyboardFocused = 0;
				e.propagate = false;
				return;
			}
			return;
		}

		if (e.keyCode == hxd.Key.UP || e.keyCode == hxd.Key.DOWN) {
			if (submenu != null && submenu.keyboardFocused >= 0) {
				submenu.keyDownHandler(isSearchBar, e);
				return;
			}
			var offset = 0;
			if (e.keyCode == hxd.Key.UP) {
				offset = -1;
			} else {
				offset = 1;
			}

			keyboardFocused = (keyboardFocused + offset + selectableElements.length) % selectableElements.length;

			searchBar.textInput.preventDefault = true;
			e.propagate = false;
			return;
		}
	}

	function keyUp(e: hxd.Event) {
		// if (parentMenu != null)
		// 	return;

		// if (e.keyCode == hxd.Key.UP || e.keyCode == hxd.Key.DOWN)
		// 	return;

		// if (!searchBar.visible) {
		// 	searchBar.visible = true;
		// 	@:privateAccess searchBar.textInput.focus();
		// 	@:privateAccess searchBar.textInput.interactive.onKeyUp(e);
		// 	e.cancel = false;
		// 	e.propagate = false;
		// }
	}

	function textInput(e: hxd.Event) {
		if (parentMenu != null)
			return;
		if (!searchBar.visible) {
			searchBar.visible = true;
			@:privateAccess searchBar.textInput.focus();
			@:privateAccess searchBar.textInput.interactive.onTextInput(e);
			e.cancel = false;
			e.propagate = false;
		}
	}

	override function close() {
		submenu?.close();
		submenu = null;
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

	function get_contextMenu() : HuiContextMenu {return Std.downcast(parent.parent, HuiContextMenu);};


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
		validate();
	}

	public function validate() {
		if (item.click != null)
			item.click();

		if (item.menu != null) {
			contextMenu.openSubmenu(this);
		}
		else if (!item.stayOpen) {
			contextMenu.close();
			contextMenu.onFinalClose();
		}
	}
}

#end