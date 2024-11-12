package hide.comp;

enum ToolType {
	Button(click: Void->Void);
	Toggle(toggle: Bool->Void);
	Range(onChange: Float->Void);
	Color(onChange: Int -> Void);
	Menu(items: Array<hide.comp.ContextMenu.MenuItem>);
	Popup(click: hide.Element -> hide.comp.Popup);
	Separator;
}

typedef ToolDef = {
	id: String,
	title : String,
	type : ToolType,
	?icon : String,
	?iconStyle: Dynamic,
	?rightClick : Void -> Void,
	?defaultValue : Dynamic,
}

typedef ToolToggle = {
	var id : String;
	var element : Element;
	function toggle( v : Bool ) : Void;
	function isDown(): Bool;
	function rightClick( v : Void -> Void ) : Void;
	function refresh() : Void;
}

typedef ToolSelect<T> = {
	var element : Element;
	function setContent( elements : Array<{ label : String, value : T }> ) : Void;
	dynamic function onSelect( v : T ) : Void;
}

typedef ToolMenu<T> = {
	var element : Element;
	function setContent( elements : Array<hide.comp.ContextMenu.MenuItem> ) : Void;
	dynamic function onSelect( v : T ) : Void;
}

class Toolbar extends Component {

	var curGroup : Element = null;
	var toggles : Array<ToolToggle>;

	public function new(?parent,?el) {
		super(parent,el);
		element.addClass("hide-toolbar2");
		newGroup();
		toggles = new Array<ToolToggle>();
	}

	public function clear() {
		element.empty();
		newGroup();
	}

	function newGroup() {
		curGroup = new Element("<div>").addClass("tb-group").appendTo(element);
	}

	public function addSeparator() {
		newGroup();
	}

	public function addButton( icon : String, ?label : String, ?onClick : Void -> Void, ?rightClick : Void -> Void ) {
		var e = new Element('<div class="button2" title="${label==null ? "" : label}"></div>');
        if (icon != "" && icon != null) {
            e.append(new Element('<div class="icon ico ico-$icon"/>'));
        }
        else {
            if (label != null && label != "") {
                e.append(new Element('<span class="label">$label</span>'));
            }
            e.addClass("menu");
        }
		if( onClick != null ) e.click(function(_) onClick());
		e.appendTo(curGroup);
		if ( rightClick != null )
			e.contextmenu(function(e) { rightClick(); e.preventDefault(); });
		return e;
	}

	public function addToggle( id: String, icon : String, ?title : String, ?label : String, ?onToggle : Bool -> Void, ?defValue = false, ?toggledIcon : String, saveToggleState = true) : ToolToggle {
		var e = new Element('<div class="button2" id="${id}" title="${title==null ? "" : title}"><div class="icon ico ico-$icon"/></div>');

		if(label != null)
			new Element('<label>$label</label>').appendTo(e);

		function tog() {
			e.get(0).toggleAttribute("checked");
			var checked = e.get(0).hasAttribute("checked");

			if (toggledIcon != null) {
				e.find(".icon").toggleClass('ico-$icon', !checked);
				e.find(".icon").toggleClass('ico-$toggledIcon', checked);
			}

			Ide.inst.currentConfig.set('sceneeditor.${id}', checked);

			if( onToggle != null ) onToggle(checked);
		}

		e.click(function(e) if( e.button == 0 ) tog());
		e.appendTo(curGroup);


		var def = defValue != null ? defValue : false;
		if( (saveToggleState && Ide.inst.currentConfig.get('sceneeditor.${id}', def)) || (!saveToggleState && def) )
			tog();

		if (saveToggleState) {
			onToggle(Ide.inst.currentConfig.get('sceneeditor.${id}', def));
		}

		return {
			id : id,
			element : e,
			toggle : function(b) tog(),
			isDown: function() return e.get(0).hasAttribute("checked"),
			rightClick : function(f) {
				e.contextmenu(function(e) { f(); e.preventDefault(); });
			},
			refresh : function() {
				if (!saveToggleState)
					return;

				var isCheck = e.get(0).hasAttribute("checked");
				if (isCheck != Ide.inst.currentConfig.get('sceneeditor.${id}', def))
					tog();
			}
		};
	}

	public function addColor( label : String, onChange : Int -> Void, ?alpha : Bool, ?defValue = 0 ) {
		var button = new Element("<div class='button2'>");
		curGroup.append(button);
		var color = new hide.comp.ColorPicker.ColorBox(button, null, true);
		color.element.height("100%");
		color.element.width("100%");
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
		var e = new Element('<div class="select" title="${label==null ? "" : label}"><div class="icon ico ico-$icon"/><select/></div>');
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
		e.appendTo(curGroup);
		return tool;
	}

	public function addMenu<T>( icon : String, label : String ) : ToolMenu<T> {
        var menu = new Element('<div class="menu"></div>');
        if (icon != null) {
            menu.append(new Element('<div class="icon ico ico-$icon"></div>'));
        }
        if (label != null && label.length > 0) {
            menu.append(new Element('<span class="label">${label==null ? "" : label}</span>'));
        }
		var menuItems : Array<hide.comp.ContextMenu.MenuItem> = [];
		var tool : ToolMenu<T> = {
			element : menu,
			setContent : function(c) {
					menuItems = c;
			},
			onSelect : function(_) {},
		};
		menu.get(0).onclick = function(ev : js.html.MouseEvent) : Void {
			if( ev.button == 0 ){
				hide.comp.ContextMenu.createDropdown(menu.get(0), menuItems);
			}
		};
		menu.appendTo(curGroup);
		return tool;
	}

	public function addRange( label : String, onChange : Float -> Void, ?defValue = 0., min = 0., max = 1., ?step:Float, ?className:String) {
		var elt = new Element('<input title="$label" type="range" min="$min" max="$max" value="$defValue">');
		if( step != null ) elt.attr("step",""+step);
		var r = new hide.comp.Range(curGroup,elt,className);
		r.onChange = function(_) onChange(r.value);
		return r;
	}

	public function addPopup(icon: String, title: String, open: hide.Element -> hide.comp.Popup, ?rightClick : Void -> Void) {
		var el = addButton(icon, title, null, rightClick);
		var p: hide.comp.Popup = null;
		el.click(function(e) {
			if (p == null) {
				p = open(el);
				p.onClose = function() {
					p = null;
				}
			}
			else {
				//p.close();
			}
		});
	}

	public function makeToolbar(toolsDefs : Array<hide.comp.Toolbar.ToolDef>, ?config : Config, ?keys : hide.ui.Keys) {
		for (tool in toolsDefs) {
			var key = null;
			if (config != null) {
				key = config.get("key.sceneeditor." + tool.id);
			}
			var shortcut = key != null ? " (" + key + ")" : "";
			var el : Element = null;
			switch(tool.type) {
				case Separator:
					addSeparator();
				case Button(f):
					el = addButton(tool.icon, tool.title + shortcut, f, tool.rightClick);
				case Toggle(f):
					var toggle = addToggle(tool.id, tool.icon, tool.title + shortcut, null, f, tool.defaultValue);
					el = toggle.element;
					if( key != null && keys != null)
						keys.register("sceneeditor." + tool.id, () -> toggle.toggle(!toggle.isDown()));
					if (tool.rightClick != null)
						toggle.rightClick(tool.rightClick);
					toggles.push(toggle);
				case Color(f):
					el = addColor(tool.title, f).element;
				case Range(f):
					el = addRange(tool.title, f, 1.).element;
				case Menu(items):
					var menu = addMenu(tool.icon, tool.title);
					menu.setContent(items);
					el = menu.element;
				case Popup(f):
					addPopup(tool.icon, tool.title + shortcut, f, tool.rightClick);
			}

			if (el != null) {
				el.get(0).setAttribute("id", tool.id);
				if(tool.iconStyle != null)
					el.find(".icon").css(tool.iconStyle);
			}
		}
	}

	public function refreshToggles() {
		for (tog in toggles)
			tog.refresh();
	}
}