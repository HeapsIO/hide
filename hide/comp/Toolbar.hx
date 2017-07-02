package hide.comp;

typedef Toggle = {
	var element : Element;
	function toggle( v : Bool ) : Void;
}

class Toolbar extends Component {

	public var bar : Element;
	public var content : Element;

	public function new(root) {
		super(root);
		var e = new Element('<div class="hide-toolbar-container"><div class="hide-toolbar"/><div class="hide-toolbar-content"/>').appendTo(root);
		bar = e.find('.hide-toolbar');
		content = e.find(".hide-toolbar-content");
	}

	public function addButton( icon : String, ?label : String, ?onClick : Void -> Void ) {
		var e = new Element('<div class="hide-toolbar-button" title="${label==null ? "" : label}"><div class="hide-toolbar-icon fa fa-$icon"/></div>');
		if( onClick != null ) e.click(function(_) onClick());
		e.appendTo(bar);
		return e;
	}

	public function addToggle( icon : String, ?label : String, ?onToggle : Bool -> Void ) : Toggle {
		var e = new Element('<div class="hide-toolbar-toggle" title="${label==null ? "" : label}"><div class="hide-toolbar-icon fa fa-$icon"/></div>');
		e.click(function(_) { e.toggleClass("toggled"); if( onToggle != null ) onToggle(e.hasClass("toggled")); });
		e.appendTo(bar);
		return { element : e, toggle : function(b) e.toggleClass("toggled",b) };
	}

}