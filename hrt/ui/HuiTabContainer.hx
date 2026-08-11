package hrt.ui;
using Lambda;

#if hui

@:access(hrt.ui.HuiTab)
@:access(hrt.ui.HuiView)
class HuiTabContainer extends HuiElement {
	static var SRC =
		<hui-tab-container>
			<hui-element id="tab-bar">
				<hui-element id="tab-bar-content"/>
				<hui-button-menu(null) id="tab-bar-more">
				</hui-button-menu>
			</hui-element>
			<hui-element id="content" __content__/>
		</hui-tab-container>

	var activeTabElement: HuiElement = null;
	var onTabDragged : (e: hxd.Event) -> Void;
	var onTabRelease : (e: hxd.Event) -> Void;

	function new(?parent) {
		super(parent);
		initComponent();

		syncTabsQueued = true;

		content.onChildrenChanged = () -> syncTabsQueued = true;

		onAfterReflow = () -> syncTabsQueued = true;
	}

	public function setTab(newElement: HuiElement) {
		if (newElement != null && content.children.indexOf(newElement) < 0)
			throw "element must be a child of content";

		if (activeTabElement != null) {
			var view = Std.downcast(activeTabElement, HuiView);
			if (view != null) {
				view.onHide();
			}
		}

		activeTabElement = newElement;

		var currentTabs : Array<HuiTab> = cast tabBarContent.childElements;
		var tab = currentTabs.find((t) -> t.targetElement == activeTabElement);
		if (tab != null) {
			if (tab.visible == false) {
				tab.visible = true;
				tabBarContent.addChildAt(tab, 0);
			}
		}

		if (activeTabElement != null) {
			var view = Std.downcast(activeTabElement, HuiView);
			if (view != null) {
				view.onDisplay();
			}
		}

		saveDisplayState("currentTab", content.childElements.indexOf(activeTabElement));

		syncActiveTabStyle();

		syncTabsQueued = true;
	}

	public function setTabIndex(tab: HuiTab, index: Int) {
		index = index + 1; // Because first child is the background
		@:privateAccess tabBarContent.children.remove(tab);
		@:privateAccess tabBarContent.children.insert(index, tab);
		syncTabs();
	}

	function getDefaultCurrentTab() : HuiElement {
		return getTabs()[0];
	}

	dynamic function onContextMenu(forElement: HuiElement) {

	}

	var syncTabsQueued = false;


	function makeTab(forElement: HuiElement) : HuiTab {
		var tab = new HuiTab(forElement);
		var index = content.childElements.indexOf(forElement);
		tabBarContent.addChildAt(tab, index);

		tab.onMove = (e) -> {
			if (onTabDragged != null)
				onTabDragged(e);
		}

		tab.onClick = (e) -> {
			switch(e.button) {
				case 0: setTab(tab.targetElement);
				case 1: onContextMenu(forElement);
				case 2: requestClose(forElement);
			}
		}

		tab.onPush = (e) -> {
			if (e.button == 0) {
				tab.dom.toggleClass("dragged", true);
				var scene = getScene();
				var newIdx = 0;
				var dropTarget = null;
				var currentTabs : Array<HuiElement> = cast getTabs();
				onTabDragged = (e) -> {
					for (idx => t in currentTabs) {
						var huiTab : HuiTab = cast getTabTab(t);
						if (scene.mouseX > huiTab.absX && scene.mouseX < huiTab.absX + huiTab.calculatedWidth)
							newIdx = idx;
					}
					dropTarget?.dom.toggleClass("dropTarget", false);
					dropTarget = getTabTab(getTabs()[newIdx]);
					dropTarget.dom.toggleClass("dropTarget", true);
				}

				onTabRelease = (e) -> {
					tab.dom.toggleClass("dragged", false);
					dropTarget?.dom.toggleClass("dropTarget", false);
					setTabIndex(tab, newIdx);
				}
			}
		}

		tab.onRelease = (e) -> {
			onTabDragged = null;
			if (onTabRelease != null)
				onTabRelease(e);
			onTabRelease = null;
		}

		return tab;
	}

	function requestClose(forElement: HuiElement) {

	}

	function syncTabs() {
		syncTabsQueued = false;

		var elements = content.childElements;

		var currentTabs : Array<HuiTab> = cast tabBarContent.childElements;
		var oldTabs: Map<{}, Bool> = [];
		for (tab in currentTabs) {
			oldTabs.set(cast tab, true);
		}

		for (element in elements) {
			var tab = currentTabs.find((t) -> t.targetElement == element);
			if (tab == null) {
				tab = makeTab(element);
			} else {
				oldTabs.remove(cast tab);
			}

			tab.title.text = element.getDisplayName();
		}

		for (old => _ in oldTabs) {
			(cast old: HuiTab).remove();
		}


		if (activeTabElement == null) {
			var newTab = getDefaultCurrentTab();
			if (newTab != null) {
				setTab(newTab);
			}
		}

		var cumulativeWidth = 0.0;
		var anyInvisible = false;

		currentTabs = cast tabBarContent.childElements;

		for (tab in currentTabs) {
			var tab : HuiTab = cast tab;

			tab.dom.toggleClass("active", tab.targetElement == activeTabElement);
			tab.reflow();

			cumulativeWidth += tab.calculatedWidth;
			tab.visible = cumulativeWidth < tabBarContent.calculatedWidth;
		}

		var invisibles : Array<HuiTab> = cast currentTabs.filter((e) -> !e.visible);
		if (invisibles.length > 0) {
			tabBarMore.visible = true;
			tabBarMore.getItems = () -> {
				return [
					for (tab in invisibles) {
						{
							label: tab.title.text,
							click: setTab.bind(tab.targetElement),
						}
					}
				];
			}
		} else {
			tabBarMore.visible = false;
		}

		for (element in elements) {
			element.visible = element == activeTabElement;
		}
	}

	public function getTabTab(forElement: HuiElement) {
		var index = getTabs().indexOf(forElement);
		return tabBarContent.childElements[index];
	}

	public function addTab(tab: HuiElement, ?index: Int) {
		content.addChildAt(tab, index ?? content.children.length);
	}

	public function removeTab(tab: HuiElement) {
		if (tab == activeTabElement) {
			var index = getTabs().indexOf(activeTabElement);
			content.removeChild(tab);
			index = hxd.Math.iclamp(index, 0, getTabs().length - 1);
			var newTab = getTabs()[index];
			if (newTab != null) {
				setTab(newTab);
			}
		} else {
			content.removeChild(tab);
		}
	}

	public function getTabs() : Array<HuiElement> {
		return content.childElements;
	}

	function syncActiveTabStyle() {
		var currentTabs : Array<HuiTab> = cast tabBarContent.childElements;

		for (tab in currentTabs) {
			var tab : HuiTab = cast tab;
			tab.dom.toggleClass("active", tab.targetElement == activeTabElement);
		}
	}

	override function sync(ctx) {
		if (syncTabsQueued)
			syncTabs();

		super.sync(ctx);
	}
}

#end