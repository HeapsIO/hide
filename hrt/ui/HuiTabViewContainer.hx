package hrt.ui;

#if hui

/**
	TabContainer specialized in displaying HuiView elements, and saving/reloading their
	state
**/
@:access(hrt.ui.HuiView)
class HuiTabViewContainer extends HuiTabContainer {

	var viewsState : Array<Dynamic>;

	override function new(?parent) {
		super(parent);
		initComponent();

		loadViewState();
	}

	function loadViewState() {
		viewsState = [
			{
				kind: "gym",
			}
		];

		content.removeChildElements();

		for (state in viewsState) {
			var success = false;
			if (state.kind != null) {
				var cl = HuiView.get(state.kind);
				if (cl != null) {
					var view : HuiView<Dynamic> = Type.createInstance(cl, [content]);
					view.state = state.data;
					continue;
				}
			}
			var error = new HuiElement(content);
			var errorText = new HuiText('Missing HuiView for kind ${state.kind}', error);
		}
	}
}

#end