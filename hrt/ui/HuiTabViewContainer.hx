package hrt.ui;

#if hui

typedef TabViewData = {
	var tabIndex: Int;
	var tabs: Array<ViewData>;
}

typedef ViewData = {
	var type: String;
	var ?state: Dynamic;
}

/**
	TabContainer specialized in displaying HuiView elements, and saving/reloading their
	state
**/
@:access(hrt.ui.HuiView)
class HuiTabViewContainer extends HuiTabContainer {

	var prevState : String;
	var firstInit = true;

	override function new(?parent) {
		super(parent);
		initComponent();
	}

	override function syncTabs() {
		super.syncTabs();

		if (!firstInit && dom.id.isDefined()) {
			var tabState : Array<ViewData> = [];

			for (child in getTabs()) {
				var view = Std.downcast(child, HuiView);
				if (view == null)
					continue;
				var state : ViewData = {type: view.getTypeName()};
				if (Reflect.fields(view.state).length > 0) {
					state.state = view.state;
				}

				tabState.push(state);
			}

			var state : TabViewData = {
				tabIndex: getTabs().indexOf(activeTabElement),
				tabs: tabState,
			}

			Reflect.setField(hide.Ide.inst.projectConfig.tabViews, dom.id.toString(), state);
			hide.Ide.inst.config.user.save();
		}
	}

	override function makeTab(forElement: HuiElement) : HuiTab {
		var tab = super.makeTab(forElement);
		tab.onClose = () -> removeTab(forElement);
		return tab;
	}

	override function sync(ctx) {
		super.sync(ctx);

		if (firstInit) {
			firstInit = false;
			loadViewState();
			syncTabs();
		}
	}

	// Restore default tab from save
	override function getDefaultCurrentTab() {
		var state = hide.Ide.inst.projectConfig.tabViews.get(dom.id.toString());
		var index = state?.tabIndex ?? 0;
		var tabs = getTabs();
		index = hxd.Math.iclamp(index, 0, tabs.length);
		return tabs[index];
	}

	function loadViewState() {
		var tabList : Array<ViewData> = [];
		if (dom.id.isDefined()) {
			var state = hide.Ide.inst.projectConfig.tabViews.get(dom.id.toString());
			tabList = state?.tabs ?? tabList;
		}

		content.removeChildElements();
		activeTabElement = null;

		for (tab in tabList) {
			var success = false;
			if (tab.type != null) {
				var cl = HuiView.get(tab.type);
				if (cl != null) {
					var view : HuiView<Dynamic> = Type.createInstance(cl, [tab.state, content]);
					continue;
				}
			}
			var error = new HuiElement(content);
			var errorText = new HuiText('Missing HuiView for type ${tab.type}', error);
		}

		syncTabsQueued = true;
	}
}

#end