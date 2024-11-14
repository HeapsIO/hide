package hide.comp;

typedef MenuItem = {
    ?label: String,
    ?isSeparator: Bool,
    ?menu: Array<MenuItem>,
    ?click: Void -> Void,
    ?enabled: Bool,
    ?stayOpen : Bool,
    ?icon: String,
    ?keys: String,
    ?checked: Bool,
    ?tooltip: String
}

// for retrocompat with the old menu system
@:deprecated("Use MenuItem instead")
typedef ContextMenuItem = hide.comp.ContextMenu.MenuItem;


enum SearchMode {
    /**
        No search bar or search functionality
    **/
    None;

    /**
        Search bar is hidden, is shown when the user starts typing anything
    **/
    Hidden;

    /**
        Search bar is always visible
    **/
    Visible;
}

typedef MenuOptions = {
    ?search: SearchMode, // default to Hidden for top level context menus
    ?widthOverride: Int, // if set, force the width of the first menu

    /**
        Used to automaticaly widthOverride based on context (see createDropdown)
    **/
    ?autoWidth: Bool,

    /**
        Set this to true if you have no icons/checkmarks in your menu and you want to hide the padding on the left of the entries names
    **/
    ?noIcons: Bool,

    /**
        If this set, it will be used to place the element if it goes offscreen like so

               | - placementWidth - |
        | --- your context menu --- |  <--
    **/
    ?placementWidth: Int,

    ?placementHeight: Int,

}

class ContextMenu {
    var rootElement : js.html.Element;
    var menu : js.html.MenuElement;
    var searchInput : js.html.InputElement;
    var searchBar : js.html.DivElement;

    var options: MenuOptions;

    var items: Array<MenuItem> = [];

    var currentSubmenu: ContextMenu = null;
    var currentSubmenuItemId: Int = -1;
    var parentMenu: ContextMenu = null;

    var originalPos: {x: Float, y:Float};

    var filter = "";
    var filteredItems : Array<MenuItem>;
    var flatItems : Array<{menuItem: MenuItem, elem: js.html.Element, index: Int}> = [];
    var selected = 0;

    var autoCleanupTimer: haxe.Timer;

    var popupTimer: haxe.Timer;
    final openDelayMs = 250;

    /**
        Create a context menu from a js event. If you have a jQuery event, just `cast` it
    **/
    public static function createFromEvent(e: js.html.MouseEvent, items: Array<MenuItem>, options: MenuOptions = null) {
        return new ContextMenu(items, cast e.target, null, {x: e.clientX, y: e.clientY}, options ?? {});
    }

    /**
        Create a context menu at the given x, y position in browser coordinates
    **/
    public static function createFromPoint(x: Float, y: Float, items: Array<MenuItem>, options: MenuOptions = null) {
        return new ContextMenu(items, null, null, {x:x, y:y}, options ?? {});
    }

    /**
        Create a context menu under the given element. Will make the dropdown menu have the width of the element if option.autoWidth is set
    **/
    public static function createDropdown(element: js.html.Element, items: Array<MenuItem>, options: MenuOptions = null) {
        options = options ?? {};
        var rect = element.getBoundingClientRect();
        if (options.autoWidth) {
            options.widthOverride = Std.int(rect.width);
        }
        options.placementWidth = options.placementWidth ?? Std.int(rect.width);
        options.placementHeight = options.placementHeight ?? -Std.int(rect.height);
        return new ContextMenu(items, element, null, {x: rect.left, y:rect.bottom}, options);
    }


    /**
        The constructor is public for backward compatibility reasons. Prefer using the static "createXXX" functions to create a
        context menu
    **/
    public function new(items: Array<MenuItem>, parentElement: js.html.Element = null, parentMenu: ContextMenu = null, absPos: {x: Float, y: Float} = null, options: MenuOptions = null) {
        this.items = items;
        this.parentMenu = parentMenu;
        if (absPos == null) {
            originalPos = {
                x: Ide.inst.mouseX,
                y: Ide.inst.mouseY,
            }
        } else {
            originalPos = absPos;
        }

        // Default options values
        options = options ?? {};
        options.search = options.search ?? Hidden;

        this.options = options;

        var nearest : js.html.Element = if (parentMenu != null) {
                parentElement;
            } else if (parentElement != null) {
                parentElement.closest("[popover]") ?? js.Browser.document.body;
            } else {
                js.Browser.document.body;
            };

        rootElement = js.Browser.document.createDivElement();
        rootElement.setAttribute("tabindex", "0");
        nearest.appendChild(rootElement);

        rootElement.classList.add("context-menu2");
        if (options.widthOverride != null)
            rootElement.style.width = '${options.widthOverride}px';
        untyped rootElement.popover = parentMenu != null ? "manual" : "auto";
        rootElement.style.left = '${0}px';
        rootElement.style.top = '${0}px';
        untyped rootElement.showPopover();

        menu = js.Browser.document.createMenuElement();
        if (options.search != None) {
            searchBar = js.Browser.document.createDivElement();
            rootElement.appendChild(searchBar);
            searchBar.classList.add("search-bar");

            searchInput = js.Browser.document.createInputElement();
            searchInput.type = "text";
            searchInput.placeholder = "Search ...";
            searchInput.onkeyup = (e:js.html.KeyboardEvent) -> {
                if (filter != searchInput.value) {
                    filter = searchInput.value;
                    refreshMenu();
                }
            }

            searchInput.onblur = (e) -> {
                rootElement.focus();
            }

            searchBar.appendChild(searchInput);
        }
        rootElement.appendChild(menu);

        rootElement.ontoggle = (e) -> {
            if (e.newState == "closed") {
                cleanup();
            }
        }

        refreshMenu();
        refreshPos();

        if (parentMenu == null) {
            rootElement.addEventListener("keydown", onGlobalKeyDown);
            if (options.search == Visible) {
                searchInput.focus();
            }
            else {
                rootElement.focus();
            }
        }

        if (parentMenu == null && parentElement != null) {
            autoCleanupTimer = new haxe.Timer(10);
            autoCleanupTimer.run = () -> {
                if (parentElement.closest("body") == null) {
                    close();
                }
            };
        }
    }

    function onGlobalKeyDown(e:js.html.KeyboardEvent) {
        if (!handleMovementKeys(e)) {
            if (searchBar != null) {
                searchBar.style.display = "block";
                searchInput.focus();
            }
        }
    }

    function refreshPos() {
        // Make sure the menu never goes out of bounds
        var rect = rootElement.getBoundingClientRect();
        var y = originalPos.y + Std.parseInt(js.Browser.window.getComputedStyle(rootElement).getPropertyValue("--offset-y"));
        var x = originalPos.x + Std.parseInt(js.Browser.window.getComputedStyle(rootElement).getPropertyValue("--offset-x"));


        if (y + rect.height > js.Browser.window.innerHeight) {
            if (parentMenu != null) {
                y = js.Browser.window.innerHeight - rect.height;
            } else {
                y = originalPos.y - rect.height;
                if (options.placementHeight != null) {
                    y += options.placementHeight;
                }
            }

        }
        if (y < 0) {
            y = 0;
        }

        if (x + rect.width > js.Browser.window.innerWidth) {
            if (parentMenu != null) {
                x = parentMenu.rootElement.getBoundingClientRect().left - rect.width;
            } else {
                // put the menu to the left of the cursor if there is no parent menu
                x = originalPos.x - rect.width;
                if (options.placementWidth != null) {
                    x += options.placementWidth;
                }
            }
        }
        if (x < 0) {
            x = 0;
        }

        rootElement.style.left = '${x}px';
        rootElement.style.top = '${y}px';
    }

    function handleMovementKeys(e: js.html.KeyboardEvent) : Bool {
        if (currentSubmenu != null) {
            trace("submenu");
            return currentSubmenu.handleMovementKeys(e);
        }
        if (e.key == "Escape") {
            close();
            return true;
        }
        else if (e.key == "ArrowUp") {
            e.preventDefault();
            updateSelection(selected - 1);
            return true;
        }
        else if (e.key == "ArrowDown") {
            e.preventDefault();
            updateSelection(selected + 1);
            return true;
        }
        else if (e.key == "Enter") {
            e.preventDefault();
            if (selected >= 0 && flatItems != null) {
                if (flatItems[selected].menuItem.menu != null) {
                    currentSubmenuItemId = flatItems[selected].index;
                    refreshSubmenu();
                    currentSubmenu.updateSelection(0);
                } else {
                    flatItems[selected].elem.click();
                }
            }
            return true;
        }
        else if (filter == "") {
            if (e.key == "ArrowRight") {
                if (selected >= 0 && flatItems[selected].menuItem.menu != null) {
                    currentSubmenuItemId = flatItems[selected].index;
                    refreshSubmenu();
                    currentSubmenu.updateSelection(0);
                }
                return true;
            }
            if (e.key == "ArrowLeft" && parentMenu != null) {
                close();
                return true;
            }
        }
        return false;
    }

    public dynamic function onClose() {

    }

    function refreshMenu() {
        if (popupTimer != null) {
            popupTimer.stop();
            popupTimer = null;
        }

        menu.innerHTML = "";

        if (filter == "") {
            flatItems = [];
            selected = -1;

            if (searchBar != null && options.search == Hidden) {
                searchBar.style.display = "none";
            }

            filteredItems = null;
            for (id => item in items) {
                if (item.isSeparator) {
                    var hr = js.Browser.document.createHRElement();
                    menu.appendChild(hr);
                } else {
                    //var li = js.Browser.document.createLIElement();
                    var li = createItem(item, id);
                    menu.appendChild(li);
                    if (item.enabled ?? true) {
                        flatItems.push({menuItem: item, elem:li, index: id});
                    }
                }
            }
        }
        else {
            filteredItems = [];
            flatItems = [];

            searchBar.style.display = "block";

            closeSubmenu();

            var filterLower = filter.toLowerCase();

            function filterElements(items: Array<MenuItem>, parentMatch: Bool) : Array<MenuItem> {
                var filteredItems : Array<MenuItem> = [];
                for (id => item in items) {
                    var match = parentMatch || (item.label != null && StringTools.contains(item.label.toLowerCase(), filterLower));
                    if (item.menu != null) {
                        var subItems = filterElements(item.menu, match);
                        if (subItems.length > 0) {
                            filteredItems.push({label: item.label, menu: subItems});
                        }
                    }
                    else {
                        if (match) {
                            filteredItems.push(item);
                        }
                    }
                }
                return filteredItems;
            }

            filteredItems = filterElements(items, false);

            var submenuStack : Array<Iterator<MenuItem>> = [];
            submenuStack.push(filteredItems.iterator());

            // avoid double separators in a row
            var lastSeparator : js.html.Element = null;
            while (submenuStack.length > 0) {
                var top = submenuStack[submenuStack.length-1];
                if (!top.hasNext()) {
                    submenuStack.pop();

                    if (submenuStack.length > 0 && lastSeparator == null) {
                        var hr = js.Browser.document.createHRElement();
                        menu.appendChild(hr);
                        lastSeparator = hr;
                    }

                    continue;
                }

                var item = top.next();
                if (item.menu != null) {
                    var li = js.Browser.document.createLIElement();
                    menu.appendChild(li);
                    li.style.setProperty("--level", '${submenuStack.length-1}');
                    li.innerText = item.label;
                    li.classList.add("submenu-inline-header");
                    lastSeparator = null;
                    submenuStack.push(item.menu.iterator());
                }
                else {
                    var li = createItem(item, flatItems.length);
                    menu.appendChild(li);
                    li.style.setProperty("--level", '${submenuStack.length-1}');
                    if (item.enabled == null || item.enabled == true) {
                        flatItems.push({menuItem: item, elem: li, index: flatItems.length});
                    }
                    lastSeparator = null;
                }
            }
            selected = -1;
            updateSelection(0);

            if (lastSeparator != null) {
                lastSeparator.remove();
            }
        }
    }

    function close() {
        cleanup();
    }

    function closeAll() {
        var menu = this;
        while(menu.parentMenu != null) {
            menu = menu.parentMenu;
        }
        menu.close();
    }

    function createItem(menuItem: MenuItem, id: Int) : js.html.Element {
        var li = js.Browser.document.createLIElement();

        var icon = null;
        if (options.noIcons == null || options.noIcons == false) {
            icon = js.Browser.document.createSpanElement();
            li.appendChild(icon);
            icon.classList.add("icon");
            if (menuItem.icon != null) {
                icon.classList.add("fa");
                icon.classList.add('fa-${menuItem.icon}');
            }
        }

        if (menuItem.tooltip != null) {
            li.title = menuItem.tooltip;
        }

        function refreshCheck() {
            if (icon != null && menuItem.checked != null) {
                icon.classList.add("fa");
                icon.classList.toggle("fa-check-square", menuItem.checked);
                icon.classList.toggle("fa-square-o", !menuItem.checked);
            }
        }

        refreshCheck();

        var span = js.Browser.document.createSpanElement();
        span.innerHTML = menuItem.label;
        span.classList.add("label");
        li.appendChild(span);

        if (menuItem.keys != null) {
            var span = js.Browser.document.createSpanElement();
            span.innerHTML = menuItem.keys;
            span.classList.add("shortcut");
            li.appendChild(span);
        }

        if (menuItem.menu != null) {
            var span = js.Browser.document.createSpanElement();
            span.classList.add("arrow");
            span.classList.add("fa");
            span.classList.add("fa-caret-right");
            li.appendChild(span);

            if (menuItem.menu.length <= 0) {
                menuItem.enabled = false;
            }
        }

        if (menuItem.enabled ?? true) {
            li.onmouseleave = (e: js.html.MouseEvent) -> {
                if (popupTimer != null) {
                    popupTimer.stop();
                    popupTimer = null;
                }
            }

            li.onmouseenter = (e: js.html.MouseEvent) -> {
                if (popupTimer != null) {
                    popupTimer.stop();
                }
                popupTimer = haxe.Timer.delay(() -> {
                    closeSubmenu();
                    currentSubmenuItemId = menuItem.menu != null ? id : -1;
                    refreshSubmenu();
                }, openDelayMs);
            }

            li.onclick = () -> {
                if (menuItem.click != null) {
                    menuItem.click();
                }
                if (menuItem.menu != null) {
                    if (popupTimer != null) {
                        popupTimer.stop();
                    }
                    closeSubmenu();
                    currentSubmenuItemId = id;
                    refreshSubmenu();
                    return;
                }
                if (menuItem.checked != null) {
                    menuItem.checked = !menuItem.checked;
                    refreshCheck();
                }
                if (!menuItem.stayOpen) {
                    closeAll();
                }
            }
        } else {
            li.classList.add("disabled");
        }

        return li;
    }

    function updateSelection(newIndex: Int) {
        if (selected != -1) {
            flatItems[selected].elem.classList.remove("highlight");
        }
        if (newIndex < 0) {
            newIndex = flatItems.length-1;
        }
        else if (newIndex > flatItems.length - 1) {
            newIndex = 0;
        }
        if (newIndex < 0 || newIndex >= flatItems.length) {
            selected = -1;
        }
        else {
            selected = newIndex;
            flatItems[selected].elem.classList.add("highlight");
            flatItems[selected].elem.scrollIntoView({block: cast "nearest"});
        }
    }

    function cleanup() {
        rootElement.remove();
        if (currentSubmenu != null) {
            currentSubmenu.close();
        }
        if (autoCleanupTimer != null) {
            autoCleanupTimer.stop();
            autoCleanupTimer = null;
        }
        if (parentMenu != null) {
            if (parentMenu.currentSubmenu != this)
                throw "parentMenu.currentSubmenu != this";
            parentMenu.currentSubmenu = null;
        }

        if (parentMenu == null) {
            rootElement.removeEventListener("keydown", onGlobalKeyDown);
        }

        onClose();
    }

    function closeSubmenu() {
        if (currentSubmenu != null) {
            var element = menu.children[currentSubmenuItemId];
            if (element != null) {
                element.classList.remove("open");
            }
            currentSubmenu.close();
            currentSubmenu = null;
            currentSubmenuItemId = -1;
        }
    }

    function refreshSubmenu() {
        if (currentSubmenu != null) {
            return;
        }
        if (currentSubmenuItemId >= 0) {
            var element = menu.children[currentSubmenuItemId];
            element.classList.add("open");
            var rect = element.getBoundingClientRect();
            currentSubmenu = new ContextMenu(items[currentSubmenuItemId].menu, rootElement, this, {x: rect.right, y: rect.top}, {search: None, noIcons: options.noIcons});
        }
    }
}