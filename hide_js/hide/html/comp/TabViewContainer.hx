package hide.html.comp;

import hide.html.WebComponent;
import js.html.Element;
import hide.ui.View;

/**
	`TabContainer` of `hide.ui.View`s, whose tabs can be dragged to other `TabViewContainer`s.
	A view is destroyed when its tab is closed.
**/
@:keep
class TabViewContainer extends TabContainer {
	public var views(default, null) : Array<View<Dynamic>> = [];

	public function addView(view : View<Dynamic>, ?before : View<Dynamic>) {
		views.insert(before == null ? views.length : views.indexOf(before), view);
		insertBefore(view.element[0], before == null ? null : before.element[0]);
		view.setContainer(this);
	}

	function getView(pane : Element) : View<Dynamic> {
		return Reflect.field(pane, "__view");
	}

	override function canDragPane(pane : Element) {
		return true;
	}

	override function canDropPane(pane : Element, from : TabContainer) {
		var view = getView(pane);
		return view != null && (view.defaultOptions.position == DisplayPosition.Center) == (id == DisplayPosition.Center);
	}

	override function canClosePane(pane : Element) {
		return getView(pane).onBeforeClose();
	}

	override function buildPaneMenu(pane : Element) {
		return getView(pane).buildTabMenu();
	}

	override function onPaneVisibilityChanged(pane : Element, visible : Bool) {
		var view = getView(pane);
		if (visible) {
			hide.tools.CrashReport.log("show " + view);
			haxe.Timer.delay(view.onActivate, 0);
		} else
			view.onHide();
		@:privateAccess hide.Ide.inst.onLayoutChanged();
	}

	override function insertPane(pane : Element, before : Element) {
		if (before == pane)
			before = pane.nextElementSibling;
		var view = getView(pane);
		view.container.views.remove(view);
		views.insert(before == null ? views.length : views.indexOf(getView(before)), view);
		view.container = this;
		super.insertPane(pane, before);
	}

	override public function close(pane : Element) {
		if (!super.close(pane))
			return false;
		var view = getView(pane);
		views.remove(view);
		view.destroy();
		return true;
	}

	static var _ = register(TabViewContainer, "hide-tab-view-container");
}
