package hrt.ui;

#if hui

typedef TabViewData = {
	var tabs: Array<ViewData>;
}

typedef ViewData = {
	var type: String;
	var ?data: Dynamic;
}

/**
	TabContainer specialized in displaying HuiView elements, and saving/reloading their
	state
**/
@:access(hrt.ui.HuiView)
class HuiTabViewContainer extends HuiTabContainer {

	var viewsState : Array<Dynamic>;
	var firstInit = true;

	override function new(?parent) {
		super(parent);
		initComponent();
	}

	override function syncTabs() {
		super.syncTabs();

		if (dom.id.isDefined() && viewsState != null) {
			Reflect.setField(hide.Ide.inst.projectConfig.tabViews, dom.id.toString(), {
				tabs: cast viewsState,
			});
			hide.Ide.inst.config.user.save();
		}

	}

	override function sync(ctx) {
		super.sync(ctx);

		if (firstInit) {
			firstInit = false;
			loadViewState();
		}
	}

	function loadViewState() {
		if (dom.id.isDefined()) {
			var tabViews = hide.Ide.inst.projectConfig.tabViews;
			viewsState = Reflect.field(tabViews, dom.id.toString())?.tabs;
		}
		viewsState ??= [
			{
				kind: "test",
			},
			{
				kind: "gym",
			}
		];

		content.removeChildElements();
		activeTabElement = null;

		for (state in viewsState) {
			var success = false;
			if (state.kind != null) {
				var cl = HuiView.get(state.kind);
				if (cl != null) {
					var view : HuiView<Dynamic> = Type.createInstance(cl, [state.state, content]);
					continue;
				}
			}
			var error = new HuiElement(content);
			var errorText = new HuiText('Missing HuiView for kind ${state.kind}', error);
		}

		syncTabsQueued = true;
	}
}

#end