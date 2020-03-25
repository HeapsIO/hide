package hide.comp;

typedef ToolToggle = {
	var element : Element;
	function toggle( v : Bool ) : Void;
	function isDown(): Bool;
	function rightClick( v : Void -> Void ) : Void;
}

typedef ToolSelect<T> = {
	var element : Element;
	function setContent( elements : Array<{ label : String, value : T }> ) : Void;
	dynamic function onSelect( v : T ) : Void;
}

class Toolbar extends Component {

	public function new(?parent,?el) {
		super(parent,el);
		element.addClass("hide-toolbar");
	}

	public function addButton( icon : String, ?label : String, ?onClick : Void -> Void ) {
		var e = new Element('<div class="button" title="${label==null ? "" : label}"><div class="icon fa fa-$icon"/></div>');
		if( onClick != null ) e.click(function(_) onClick());
		e.appendTo(element);
		return e;
	}

	public function addToggle( icon : String, ?title : String, ?label : String, ?onToggle : Bool -> Void, ?defValue = false ) : ToolToggle {
		var e = new Element('<div class="toggle" title="${title==null ? "" : title}"><div class="icon fa fa-$icon"/></div>');
		if(label != null) {
			new Element('<label>$label</label>').appendTo(e);
		}
		function tog() {
			e.toggleClass("toggled");
			this.saveDisplayState("toggle:" + icon, e.hasClass("toggled"));
			if( onToggle != null ) onToggle(e.hasClass("toggled"));
		}
		e.click(function(e) if( e.button == 0 ) tog());
		e.appendTo(element);
		if( defValue ) e.addClass("toggled");
		var def = getDisplayState("toggle:" + icon);
		if( def == null ) def = false;
		if( def != defValue ) e.click();
		return {
			element : e,
			toggle : function(b) tog(),
			isDown: function() return e.hasClass("toggled"),
			rightClick : function(f) {
				e.contextmenu(function(e) { f(); e.preventDefault(); });
			}
		};
	}

	public function addColor( label : String, onChange : Int -> Void, ?alpha : Bool, ?defValue = 0 ) {
		var color = new hide.comp.ColorPicker(alpha, element);
		color.onChange = function(move) {
			if( !move ) this.saveDisplayState("color:" + label, color.value);
			onChange(color.value);
		};
		var def = getDisplayState("color:" + label);
		if( def == null ) def = defValue;
		color.value = def;
		onChange(def);
		return color;
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
		e.appendTo(element);
		return tool;
	}

	public function addRange( label : String, onChange : Float -> Void, ?defValue = 0., min = 0., max = 1. ) {
		var r = new hide.comp.Range(element,new Element('<input title="$label" type="range" min="$min" max="$max" value="$defValue">'));
		r.onChange = function(_) onChange(r.value);
		return r;
	}

}