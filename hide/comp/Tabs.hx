package hide.comp;

class Tabs extends Component {

	public var currentTab(default, set) : Element;
	var header : Element;

	public function new(root) {
		super(root);
		root.addClass("hide-tabs");
		header = new Element("<div>").addClass("tabs-header").prependTo(root);
		syncTabs();
		currentTab = new Element(getTabs()[0]);
	}

	function set_currentTab( e : Element ) {
		getTabs().hide();
		e.show();
		header.children().removeClass("active").filter("[index=" + e.attr("index") + "]").addClass("active");
		return currentTab = e;
	}

	public function getTabs() : Element {
		return root.children(".tab");
	}

	function syncTabs() {
		header.html("");
		var index = 0;
		for( t in getTabs().elements() ) {
			var icon = t.attr("icon");
			var name = t.attr("name");
			var index = index++;
			var tab = new Element("<div>").html( (icon != null ? '<div class="fa fa-$icon"></div> ' : '') + (name != null ? name : '') );
			t.attr("index", index);
			tab.attr("index", index);
			tab.appendTo(header);
			tab.click(function(_) currentTab = t);
		}
	}

}