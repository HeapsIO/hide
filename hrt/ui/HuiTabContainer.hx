package hrt.ui;

#if hui

@:access(hrt.ui.HuiTab)
class HuiTabContainer extends HuiElement {
	static var SRC =
		<hui-tab-container>
			<hui-element id="tab-bar"/>
			<hui-element id="content" __content__/>
		</hui-tab-container>

	var activeTabIndex = 0;
	var lastActiveTabIndex = -1;

	function new(?parent) {
		super(parent);
		initComponent();

		syncTabsQueued = true;
	}

	function setTab(id: Int) {
		activeTabIndex = id;

		syncTabsQueued = true;
	}

	var syncTabsQueued = false;

	dynamic function onTabChange(newTab: Int, oldTab: Int) {

	}

	function syncTabs() {
		if (syncTabsQueued) {
			if (activeTabIndex != lastActiveTabIndex) {
				onTabChange(activeTabIndex, lastActiveTabIndex);
				lastActiveTabIndex = activeTabIndex;
			}

			var elements = content.childElements;

			syncTabsQueued = false;
			if (tabBar.childElements.length != elements.length) {
				tabBar.removeChildren();
				for (i in 0...elements.length) {
					var tab = new HuiTab(tabBar);
					tab.onClick = (e) -> setTab(i);
				}
			}

			for (i => tab in tabBar.childElements) {
				var tab : HuiTab = cast tab;
				tab.title.text = elements[i].getDisplayName();

				tab.dom.toggleClass("active", activeTabIndex == i);
			}
		}
	}

	override function sync(ctx) {
		var elements = content.childElements;

		syncTabs();

		for (i => element in elements) {
			element.visible = i == activeTabIndex;
		}

		super.sync(ctx);
	}
}

#end