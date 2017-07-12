package hide.comp;

typedef ToolToggle = {
	var element : Element;
	function toggle( v : Bool ) : Void;
}

typedef ToolSelect<T> = {
	var element : Element;
	function setContent( elements : Array<{ label : String, value : T }> ) : Void;
	dynamic function onSelect( v : T ) : Void;
}

class Toolbar extends Component {

	public var bar : Element;
	public var content : Element;

	public function new(root) {
		super(root);
		var e = new Element('<div class="hide-toolbar"><div class="toolbar"/><div class="content"/>').appendTo(root);
		bar = e.find('.toolbar');
		content = e.find(".content");
	}

	public function addButton( icon : String, ?label : String, ?onClick : Void -> Void ) {
		var e = new Element('<div class="button" title="${label==null ? "" : label}"><div class="icon fa fa-$icon"/></div>');
		if( onClick != null ) e.click(function(_) onClick());
		e.appendTo(bar);
		return e;
	}

	public function addToggle( icon : String, ?label : String, ?onToggle : Bool -> Void ) : ToolToggle {
		var e = new Element('<div class="toggle" title="${label==null ? "" : label}"><div class="icon fa fa-$icon"/></div>');
		e.click(function(_) { e.toggleClass("toggled"); if( onToggle != null ) onToggle(e.hasClass("toggled")); });
		e.appendTo(bar);
		return { element : e, toggle : function(b) e.toggleClass("toggled",b) };
	}

	public function addSelect<T>( icon : String, ?label : String ) : ToolSelect<T> {
		var e = new Element('<div class="select" title="${label==null ? "" : label}"><div class="icon fa fa-$icon"/><select/></div>');
		var content : Array<{ label : String, value : T }> = [];
		var select = e.find("select");
		var tool : ToolSelect<T> = {
			element : e,
			setContent : function(c) {
				select.html("");
				content = c;
				for( i in 0...content.length )
					new Element('<option value="$i">${content[i].label}</option>').appendTo(select);
			},
			onSelect : function(_) {},
		};
		select.change(function(_) tool.onSelect(content[Std.parseInt(select.val())].value));
		e.appendTo(bar);
		return tool;
	}

}