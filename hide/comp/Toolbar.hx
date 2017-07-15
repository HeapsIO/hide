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

	public function new(root) {
		super(root);
		root.addClass("hide-toolbar");
	}

	public function addButton( icon : String, ?label : String, ?onClick : Void -> Void ) {
		var e = new Element('<div class="button" title="${label==null ? "" : label}"><div class="icon fa fa-$icon"/></div>');
		if( onClick != null ) e.click(function(_) onClick());
		e.appendTo(root);
		return e;
	}

	public function addToggle( icon : String, ?label : String, ?onToggle : Bool -> Void, ?defValue = false ) : ToolToggle {
		var e = new Element('<div class="toggle" title="${label==null ? "" : label}"><div class="icon fa fa-$icon"/></div>');
		e.click(function(_) {
			e.toggleClass("toggled");
			this.saveDisplayState("toggle:" + icon, e.hasClass("toggled"));
			if( onToggle != null ) onToggle(e.hasClass("toggled"));
		});
		e.appendTo(root);
		if( defValue ) e.addClass("toggled");
		var def = getDisplayState("toggle:" + icon);
		if( def == null ) def = false;
		if( def != defValue ) e.click();
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
		e.appendTo(root);
		return tool;
	}

}