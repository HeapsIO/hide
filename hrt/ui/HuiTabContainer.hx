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

		saveDisplayState("currentTab", childElements.indexOf(activeTabElement));

		syncActiveTabStyle();

		syncTabsQueued = true;
	}

	function getDefaultCurrentTab() : HuiElement {
		return getTabs()[0];
	}

	function closeTab(id: Int) {

	}

	var syncTabsQueued = false;


	function makeTab(forElement: HuiElement) : HuiTab {
		var tab = new HuiTab(forElement, tabBarContent);
		tab.onClick = (e) -> setTab(tab.targetElement);
		tab.title.text = forElement.getDisplayName();
		return tab;
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

	public function addTab(tab: HuiElement) {
		content.addChild(tab);
	}

	public function removeTab(tab: HuiElement) {
		content.removeChild(tab);
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