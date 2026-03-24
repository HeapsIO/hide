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

	override function set_needReflow(v:Bool):Bool {
		return super.set_needReflow(v);
	}

	override function new(?parent) {
		super(parent);
		initComponent();

		onContextMenu = (forElement: HuiElement) -> {
			var tab = getTabTab(forElement);
			if (tab == null)
				return;
			var tabContent : Array<hide.comp.ContextMenu.MenuItem> = [];

			tabContent.push({label: "Close", click: requestClose.bind(cast forElement)});
			tabContent.push({label: "Reload", click: () -> {
					var view : HuiView<Dynamic> = cast forElement;
					if (view == null)
						return;
					view.requestClose((canClose) -> {
						var index = getTabs().indexOf(forElement);
						removeTab(forElement);
						var state = getViewState(forElement);
						var newView = loadView(state);
						content.addChildAt(newView, index);
						activeTabElement = newView;
					});
				}
			});
			tabContent.push({isSeparator: true});

			var view = Std.downcast(forElement, HuiView);
			if (view != null)
				view.getContextMenuContent(tabContent);

			uiBase.openMenu(tabContent, {}, {object: Element(tab), directionX: StartInside, directionY: EndOutside});
		}
	}

	override function syncTabs() {
		super.syncTabs();

		if (!firstInit && dom.id.isDefined()) {
			var tabState : Array<ViewData> = [];

			for (child in getTabs()) {
				tabState.push(getViewState(child));
			}

			var state : TabViewData = {
				tabIndex: getTabs().indexOf(activeTabElement),
				tabs: tabState,
			}

			Reflect.setField(hide.Ide.inst.projectConfig.tabViews, dom.id.toString(), state);
			hide.Ide.inst.config.user.save();
		}
	}

	function getViewState(element: HuiElement) : ViewData {
		var view = Std.downcast(element, HuiView);
		if (view == null)
			return null;
		var state : ViewData = {type: view.getTypeName()};
		if (Reflect.fields(view.state).length > 0) {
			state.state = view.state;
		}
		return state;
	}

	override function makeTab(forElement: HuiElement) : HuiTab {
		var tab = super.makeTab(forElement);
		tab.onClose = requestClose.bind(cast forElement);
		return tab;
	}

	function requestClose(forElement: HuiView<Dynamic>) {
		forElement.requestClose((canClose:Bool) -> {
			if (canClose) {
				removeTab(forElement);
			}
		});
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
			loadView(tab);
		}
	}

	function loadView(data: ViewData) : HuiView<Dynamic> {
		var success = false;
		syncTabsQueued = true;
		if (data.type != null) {
			var cl = HuiView.get(data.type);
			if (cl != null) {
				var view : HuiView<Dynamic> = Type.createInstance(cl, [data.state, content]);
				return view;
			}
		}
		var error = new HuiElement(content);
		var errorText = new HuiText('Missing HuiView for type ${data.type}', error);
		return null;
	}
}

#end