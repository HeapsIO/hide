package hide.comp;

enum ToolType {
	Button;
	Toggle;
	Range;
	Color;
	Menu;
}

class ToolsObject {
	static public var prefabView : hide.view.Prefab;
	static var texContent : Element = null;
	static public var tools : Map<String, {title : String, ?icon : String, type : ToolType, ?iconTransform : String, ?rightClick : Void -> Void, ?buttonFunction : Void -> Void, ?toggleFunction : Bool -> Void, ?rangeFunction : Float -> Void, ?colorFunction : Int -> Void, ?menuItems : () -> Array<hide.comp.ContextMenu.ContextMenuItem>}> = [
		"perspectiveCamera" => {title : "Perspective camera", icon : "video-camera", type : Button, buttonFunction : () -> @:privateAccess prefabView.resetCamera(false)},
		"topCamera" => {title : "Top camera", icon : "video-camera", type : Button, iconTransform : "rotateZ(90deg)", buttonFunction : () -> @:privateAccess prefabView.resetCamera(true)},
		"snapToGroundToggle" => {title : "Snap to ground", icon : "anchor", type : Toggle, toggleFunction : (v) -> prefabView.sceneEditor.snapToGround = v},
		"localTransformsToggle"=> {title : "Local transforms", icon : "compass", type : Toggle, toggleFunction : (v) -> prefabView.sceneEditor.localTransform = v},
		"gridToggle" => {title : "Toggle grid", icon : "th", type : Toggle, toggleFunction : (v) -> { @:privateAccess prefabView.showGrid = v; @:privateAccess prefabView.updateGrid(); }},
		"bakeLights" => {title : "Bake lights", icon : "lightbulb-o", type : Button, buttonFunction : () -> @:privateAccess prefabView.bakeLights()},
		"sceneeditor.sceneInformationToggle" => {title : "Scene information", icon : "info-circle", type : Toggle, toggleFunction : (b) -> @:privateAccess prefabView.statusText.visible = b, rightClick : () -> {
			if( texContent != null ) {
				texContent.remove();
				texContent = null;
			}
			new hide.comp.ContextMenu([
				{
					label : "Show Texture Details",
					click : function() {
						var memStats = @:privateAccess prefabView.scene.engine.mem.stats();
						var texs = @:privateAccess prefabView.scene.engine.mem.textures;
						var list = [for(t in texs) {
							n: '${t.width}x${t.height}  ${t.format}  ${t.name}',
							size: t.width * t.height
						}];
						list.sort((a, b) -> Reflect.compare(b.size, a.size));
						var content = new Element('<div tabindex="1" class="overlay-info"><h2>Scene info</h2><pre></pre></div>');
						new Element(@:privateAccess prefabView.element[0].ownerDocument.body).append(content);
						var pre = content.find("pre");
						pre.text([for(l in list) l.n].join("\n"));
						texContent = content;
						content.blur(function(_) {
							content.remove();
							texContent = null;
						});
					}
				}
			]);
		}},
		"sceneeditor.autoSyncToggle" => {title : "Auto synchronize", icon : "refresh", type : Toggle, toggleFunction : (b) -> @:privateAccess prefabView.autoSync = b},
		"graphicsFilters" => {title : "Graphics filters", type : Menu, menuItems : () -> @:privateAccess prefabView.filtersToMenuItem(prefabView.graphicsFilters, "Graphics")},
		"sceneFilters" => {title : "Scene filters", type : Menu, menuItems : () -> @:privateAccess prefabView.filtersToMenuItem(prefabView.sceneFilters, "Scene")},
		"sceneeditor.backgroundColor" => {title : "Background Color", type : Color, colorFunction :  function(v) {
			@:privateAccess prefabView.scene.engine.backgroundColor = v;
			@:privateAccess prefabView.updateGrid();}},
		"sceneeditor.sceneSpeed" => {title : "Speed", type : Range, rangeFunction : function(v) @:privateAccess prefabView.scene.speed = v}
	];
}
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

typedef ToolMenu<T> = {
	var element : Element;
	function setContent( elements : Array<hide.comp.ContextMenu.ContextMenuItem> ) : Void;
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
		var def = getDisplayState("toggle:" + icon);
		if( def == null ) def = defValue;
		if( def )
			tog(); // false -> true
		else if( defValue ) {
			e.toggleClass("toggled");
			tog(); // true -> false
		}
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

	public function addMenu<T>( icon : String, label : String ) : ToolMenu<T> {
		var e = new Element('<div class="button"><div class="icon fa fa-$icon"/>${label==null ? "" : label}</div>');
		var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
		var tool : ToolMenu<T> = {
			element : e,
			setContent : function(c) {
					menuItems = c;
			},
			onSelect : function(_) {},
		};
		e.click(function(ev) if( ev.button == 0 ){
			new hide.comp.ContextMenu(menuItems);
		});
		e.appendTo(element);
		return tool;
	}

	public function addRange( label : String, onChange : Float -> Void, ?defValue = 0., min = 0., max = 1. ) {
		var r = new hide.comp.Range(element,new Element('<input title="$label" type="range" min="$min" max="$max" value="$defValue">'));
		r.onChange = function(_) onChange(r.value);
		return r;
	}

}