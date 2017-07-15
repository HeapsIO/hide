package hide.comp;

class PropsEditor extends Component {

	public var panel : Element;
	public var content : Element;
	public var undo : hide.ui.UndoHistory;
	public var saveKey : String;
	var fields : Array<PropsField>;

	public function new(root,?undo) {
		super(root);
		this.undo = undo == null ? new hide.ui.UndoHistory() : undo;
		var e = new Element("<div class='hide-properties'><div class='content'></div><div class='panel'></div></div>").appendTo(root);
		content = e.find(".content");
		panel = e.find(".panel");
		fields = [];
	}

	public function clear() {
		panel.html('');
		fields = [];
	}

	public function addMaterial( m : h3d.mat.Material, props : Dynamic, ?parent : Element ) {
		var def = h3d.mat.MaterialSetup.current.editMaterial(props);
		def = add(def, props);
		def.find("input,select").change(function(_) {
			m.props = props;
			def.remove();
			addMaterial(m, props, parent);
		});
		if( parent != null && parent.length != 0 ) def.appendTo(parent);
	}

	function getState( key : String ) : Dynamic {
		if( saveKey == null )
			return null;
		var v = js.Browser.window.localStorage.getItem("propeditor/" + key);
		if( v == null )
			return null;
		return haxe.Json.parse(v);
	}

	function saveState( key : String, value : Dynamic ) {
		if( saveKey == null )
			return;
		js.Browser.window.localStorage.setItem("propeditor/" + key, haxe.Json.stringify(value));
	}

	public function add( e : Element, ?context : Dynamic ) {

		e.appendTo(panel);
		e = e.wrap("<div></div>").parent(); // necessary to have find working on top level element

		e.find("input[type=checkbox]").wrap("<div class='checkbox-wrapper'></div>");

		e.find("input[type=range]").not("[step]").attr("step", "any");

		// -- reload states ---
		for( h in e.find(".section > h1").elements() )
			if( getState("section:" + StringTools.trim(h.text())) != false )
				h.parent().addClass("open");

		for( group in e.find(".group").elements() ) {
			var s = group.closest(".section");
			var key = (s.length == 0 ? "" : StringTools.trim(s.children("h1").text()) + "/") + group.attr("name");
			if( getState("group:" + key) != false )
				group.addClass("open");
		}

		// init section
		e.find(".section").not(".open").children(".content").hide();
		e.find(".section > h1").mousedown(function(e) {
			if( e.button != 0 ) return;
			var section = e.getThis().parent();
			section.toggleClass("open");
			section.children(".content").slideToggle(100);
			saveState("section:" + StringTools.trim(e.getThis().text()), section.hasClass("open"));
		}).find("input").mousedown(function(e) e.stopPropagation());

		for( g in e.find(".group").elements() ) {
			g.wrapInner("<div class='content'></div>'");
			if( g.attr("name") != null ) new Element("<div class='title'>" + g.attr("name") + '</div>').prependTo(g);
		}

		// init group
		e.find(".group").not(".open").children(".content").hide();
		e.find(".group > .title").mousedown(function(e) {
			if( e.button != 0 ) return;
			var group = e.getThis().parent();
			group.toggleClass("open");
			group.children(".content").slideToggle(100);

			var s = group.closest(".section");
			var key = (s.length == 0 ? "" : StringTools.trim(s.children("h1").text()) + "/") + group.attr("name");
			saveState("group:" + key, group.hasClass("open"));

		}).find("input").mousedown(function(e) e.stopPropagation());

		// init input reflection
		for( f in e.find("[field]").elements() )
			fields.push(new PropsField(this,f,context));

		return e;
	}

}


class PropsField extends Component {

	var props : PropsEditor;
	var fname : String;
	var context : Dynamic;
	var current : Dynamic;
	var enumValue : Enum<Dynamic>;
	var tempChange : Bool;
	var beforeTempChange : { value : Dynamic };
	var tselect : hide.comp.TextureSelect;
	var viewRoot : Element;

	public function new(props, f, context) {
		super(f);
		viewRoot = root.closest(".lm_content");
		this.props = props;
		this.context = context;
		Reflect.setField(f[0],"propsField", this);
		fname = f.attr("field");
		current = Reflect.field(context, fname);
		switch( f.attr("type") ) {
		case "checkbox":
			f.prop("checked", current);
			f.change(function(_) {
				props.undo.change(Field(context, fname, current), function() {
					var f = resolveField();
					f.current = Reflect.field(f.context, fname);
					f.root.prop("checked", f.current);
				});
				current = f.prop("checked");
				Reflect.setProperty(context, fname, current);
			});
			return;
		case "texture":
			tselect = new hide.comp.TextureSelect(f);
			tselect.value = current;
			tselect.onChange = function() {
				props.undo.change(Field(context, fname, current), function() {
					var f = resolveField();
					f.current = Reflect.field(f.context, fname);
					f.tselect.value = f.current;
				});
				current = tselect.value;
				Reflect.setProperty(context, fname, current);
			}
			return;
		default:
		}

		if( f.is("select") ) {
			enumValue = Type.getEnum(current);
			if( enumValue != null && f.find("option").length == 0 ) {
				for( c in enumValue.getConstructors() )
					new Element('<option value="$c">$c</option>').appendTo(f);
			}
		}

		if( f.is("[type=range]") )
			f.on("input", function(_) { tempChange = true; f.change(); });

		f.val(current);
		f.keyup(function(e) {
			if( e.keyCode == 13 ) {
				f.blur();
				return;
			}
			if( e.keyCode == 27 ) {
				f.blur();
				return;
			}
			tempChange = true;
			f.change();
		});
		f.change(function(e) {

			var newVal : Dynamic = f.val();

			if( f.is("[type=range]") || f.is("[type=number]") )
				newVal = Std.parseFloat(newVal);

			if( enumValue != null )
				newVal = Type.createEnum(enumValue, newVal);

			if( f.is("select") ) f.blur();

			if( current == newVal ) {
				if( tempChange || beforeTempChange == null )
					return;
				current = beforeTempChange.value;
				beforeTempChange = null;
			}

			if( tempChange ) {
				tempChange = false;
				if( beforeTempChange == null ) beforeTempChange = { value : current };
			}
			else {
				props.undo.change(Field(context, fname, current), function() {
					var f = resolveField();
					f.current = Reflect.field(f.context, fname);
					f.root.val(f.current);
				});
			}
			current = newVal;
			Reflect.setProperty(context, fname, newVal);
		});
	}

	function resolveField() {
		/*
			If our panel has been removed but another bound to the same object has replaced it (a refresh for instance)
			let's try to locate the field with same context + name to refresh it instead
		*/

		for( f in viewRoot.find("[field]") ) {
			var p : PropsField = Reflect.field(f, "propsField");
			if( p != null && p.context == context && p.fname == fname )
				return p;
		}

		return this;
	}

}
