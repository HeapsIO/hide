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
}

class ContextMenu2 {
    var rootElement : js.html.Element;
    var menu : js.html.MenuElement;
    var seachBar : js.html.InputElement;

    var items: Array<MenuItem> = [];

    var currentSubmenu: ContextMenu2 = null;
    var currentSubmenuItemId: Int = -1;
    var parentMenu: ContextMenu2 = null;

    var originalPos: {x: Float, y:Float};

    var filter = "";
    var filteredItems : Array<MenuItem>;
    var flatItems : Array<{menuItem: MenuItem, elem: js.html.Element, index: Int}> = [];
    var selected = 0;

    var popupTimer: haxe.Timer;
    final openDelayMs = 250;

    public static function fromEvent(e: js.html.MouseEvent, items: Array<MenuItem>) {
        return new ContextMenu2(cast e.target, null, {x: e.clientX, y: e.clientY}, items, true);
    }

    public static function createFromPoint(x: Float, y: Float , items: Array<MenuItem>) {
        return new ContextMenu2(null, null, {x:x, y:y}, items, true);
    }

    function new(parentElement: js.html.Element, parentMenu: ContextMenu2, absPos: {x: Float, y: Float}, items: Array<MenuItem>, wantSearch: Bool) {
        this.items = items;
        this.parentMenu = parentMenu;
        originalPos = absPos;

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
        untyped rootElement.popover = parentMenu != null ? "manual" : "auto";
        rootElement.style.left = '${0}px';
        rootElement.style.top = '${0}px';
        untyped rootElement.showPopover();

        menu = js.Browser.document.createMenuElement();
        if (wantSearch) {
            seachBar = js.Browser.document.createInputElement();
            seachBar.type = "text";
            seachBar.onkeyup = (e:js.html.KeyboardEvent) -> {
                if (filter != seachBar.value) {
                    filter = seachBar.value;
                    refreshMenu();
                }
            }

            seachBar.onblur = (e) -> {
                rootElement.focus();
            }

            rootElement.appendChild(seachBar);
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
            rootElement.focus();
        }
    }

    function onGlobalKeyDown(e:js.html.KeyboardEvent) {
        if (!handleMovementKeys(e)) {
            if (seachBar != null) {
                seachBar.style.display = "block";
                seachBar.focus();
            }
        }
    }

    function refreshPos() {
        var rect = rootElement.getBoundingClientRect();
        var y = originalPos.y + Std.parseInt(js.Browser.window.getComputedStyle(rootElement).getPropertyValue("--offset-y"));
        var x = originalPos.x + Std.parseInt(js.Browser.window.getComputedStyle(rootElement).getPropertyValue("--offset-x"));


        if (y + rect.height > js.Browser.window.innerHeight) {
            y = js.Browser.window.innerHeight - rect.height;
        }
        if (y < 0) {
            y = 0;
        }

        if (x + rect.width > js.Browser.window.innerWidth) {
            if (parentMenu != null) {
                x = parentMenu.rootElement.getBoundingClientRect().left - rect.width;
            }
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

    function refreshMenu() {
        if (popupTimer != null) {
            popupTimer.stop();
            popupTimer = null;
        }

        menu.innerHTML = "";

        if (filter == "") {
            flatItems = [];
            selected = -1;

            if (seachBar != null) {
                seachBar.style.display = "none";
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

            seachBar.style.display = "block";

            closeSubmenu();

            var filterLower = filter.toLowerCase();

            function filterElements(items: Array<MenuItem>) : Array<MenuItem> {
                var filteredItems : Array<MenuItem> = [];
                for (id => item in items) {
                    if (item.menu != null) {
                        var subItems = filterElements(item.menu);
                        if (subItems.length > 0) {
                            filteredItems.push({label: item.label, menu: subItems});
                        }
                    }
                    else {
                        if (item.label != null && StringTools.contains(item.label.toLowerCase(), filterLower)) {
                            filteredItems.push(item);
                        }
                    }
                }
                return filteredItems;
            }

            filteredItems = filterElements(items);

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

        var icon = js.Browser.document.createSpanElement();
        li.appendChild(icon);
        icon.classList.add("icon");
        if (menuItem.icon != null) {
            icon.classList.add("fa");
            icon.classList.add('fa-${menuItem.icon}');
        }

        function refreshCheck() {
            if (menuItem.checked != null) {
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
        if (parentMenu != null) {
            if (parentMenu.currentSubmenu != this)
                throw "parentMenu.currentSubmenu != this";
            parentMenu.currentSubmenu = null;
        }

        if (parentMenu == null) {
            rootElement.removeEventListener("keydown", onGlobalKeyDown);
        }
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
            currentSubmenu = new ContextMenu2(rootElement, this, {x: rect.right, y: rect.top}, items[currentSubmenuItemId].menu, false);
        }
    }
}