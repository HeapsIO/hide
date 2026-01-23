package hrt.ui;

#if hui

@:access(hrt.ui.HuiTab)
@:access(hrt.ui.HuiView)
class HuiTabContainer extends HuiElement {
	static var SRC =
		<hui-tab-container>
			<hui-element id="tab-bar"/>
			<hui-element id="content" __content__/>
		</hui-tab-container>

	var activeTabElement: HuiElement = null;

	function new(?parent) {
		super(parent);
		initComponent();

		syncTabsQueued = true;

		content.onChildrenChanged = () -> syncTabsQueued = true;
	}

	function setTab(newElement: HuiElement) {
		if (newElement != null && content.children.indexOf(newElement) < 0)
			throw "element must be a child of content";

		if (activeTabElement != null) {
			var view = Std.downcast(activeTabElement, HuiView);
			if (view != null) {
				view.onHide();
			}
		}

		activeTabElement = newElement;

		if (activeTabElement != null) {
			var view = Std.downcast(activeTabElement, HuiView);
			if (view != null) {
				view.onDisplay();
			}
		}

		syncTabsQueued = true;
	}

	function closeTab(id: Int) {

	}

	var syncTabsQueued = false;

	function syncTabs() {
		var elements = content.childElements;
		if (activeTabElement == null && elements.length > 0) {
			setTab(elements[0]);
		}

		var activeTabIndex = elements.indexOf(activeTabElement);

		syncTabsQueued = false;
		if (tabBar.childElements.length != elements.length) {
			tabBar.removeChildElements();
			for (i in 0...elements.length) {
				var tab = new HuiTab(tabBar);
				tab.onClick = (e) -> setTab(elements[i]);
			}
		}

		for (i => tab in tabBar.childElements) {
			var tab : HuiTab = cast tab;
			tab.title.text = elements[i].getDisplayName();

			tab.dom.toggleClass("active", activeTabIndex == i);
		}

		for (i => element in elements) {
			element.visible = i == activeTabIndex;
		}
	}

	override function sync(ctx) {
		if (syncTabsQueued)
			syncTabs();

		super.sync(ctx);
	}
}

#end