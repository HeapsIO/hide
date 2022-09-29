package hide.comp;

class Tabs extends Component {

	public var currentTab(default, set) : Element;
	var header : Element;

	public function new(?parent,?el,bottomTabs=false) {
		super(parent,el);
		element.addClass("hide-tabs");
		if( bottomTabs ) element.addClass("tabs-bottom");
		header = new Element("<div>").addClass("tabs-header").prependTo(element);
		syncTabs();
		var t = getTabs()[0];
		if( t != null ) currentTab = new Element(t);
	}

	public function createTab( title : String, ?icon : String ) {
		var e = new Element('<div class="tab" name="$title">');
		if( icon != null ) e.attr("icon",icon);
		e.appendTo(element);
		syncTabs();
		if( currentTab == null )
			currentTab = e;
		return e;
	}

	public function getHeader( tab : Element ) {
		var index = [for( t in getTabs() ) t].indexOf(tab[0]);
		if( index < 0 ) return null;
		return header.find('[index=$index]');
	}

	public function allowMask(scene : hide.comp.Scene) {
		new Element('<a href="#" class="maskToggle"></a>').prependTo(element).click((_) -> {
			element.toggleClass("masked");
			@:privateAccess scene.window.checkResize();
		});
	}

	function set_currentTab( e : Element ) {
		var index = Std.parseInt(e.attr("index"));
		getTabs().hide();
		header.children().removeClass("active").filter("[index=" + index + "]").addClass("active");
		currentTab = e;
		e.show();
		onTabChange(index);
		return e;
	}

	public function getTabs() : Element {
		return element.children(".tab");
	}

	public dynamic function onTabRightClick( index : Int ) {
	}

	public dynamic function onTabChange( index : Int ) {
	}

	function syncTabs() {
		header.html("");
		var index = 0;
		for( t in getTabs().elements() ) {
			var icon = t.attr("icon");
			var name = t.attr("name");
			var index = index++;
			var tab = new Element("<div>").html( (icon != null ? '<div class="ico ico-$icon"></div> ' : '') + (name != null ? name : '') );
			t.attr("index", index);
			tab.attr("index", index);
			tab.appendTo(header);
			tab.click(function(e) {
				currentTab = t;
			}).contextmenu(function(e) {
				e.preventDefault();
				onTabRightClick(index);
			});
		}
		if( currentTab != null )
			this.currentTab = currentTab;
	}

}