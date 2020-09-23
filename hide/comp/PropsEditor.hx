package hide.comp;
import hrt.prefab.Props;

class PropsEditor extends Component {

	public var undo : hide.ui.UndoHistory;
	public var lastChange : Float = 0.;
	public var fields(default, null) : Array<PropsField>;
	public var isTempChange = false;

	public function new(?undo,?parent,?el) {
		super(parent,el);
		element.addClass("hide-properties");
		this.undo = undo == null ? new hide.ui.UndoHistory() : undo;
		fields = [];
	}

	public function clear() {
		element.empty();
		fields = [];
	}

	public function addMaterial( m : h3d.mat.Material, ?parent : Element, ?onChange ) {
		var def = m.editProps();
		def = add(def, m.props, function(name) {
			m.refreshProps();
			if( !isTempChange ) {
				def.remove();
				addMaterial(m, parent, onChange);
				if( onChange != null ) onChange(name);
			}
		});
		if( parent != null && parent.length != 0 )
			def.appendTo(parent);
	}

	public static function makePropEl(p: PropDef, parent: Element) {
		switch( p.t ) {
		case PInt(min, max):
			var e = new Element('<input type="range" field="${p.name}" step="1">').appendTo(parent);
			if( min != null ) e.attr("min", "" + min);
			if(p.def != null) e.attr("value", "" + p.def);
			e.attr("max", "" + (max == null ? 100 : max));
		case PFloat(min, max):
			var e = new Element('<input type="range" field="${p.name}">').appendTo(parent);
			if(p.def != null) e.attr("value", "" + p.def);
			if( min != null ) e.attr("min", "" + min);
			if( max != null ) e.attr("max", "" + max);
		case PBool:
			new Element('<input type="checkbox" field="${p.name}">').appendTo(parent);
		case PTexture:
			new Element('<input type="texturepath" field="${p.name}">').appendTo(parent);
		case PUnsupported(text):
			new Element('<font color="red">' + StringTools.htmlEscape(text) + '</font>').appendTo(parent);
		case PVec(n, min, max):
			var isColor = p.name.toLowerCase().indexOf("color") >= 0;
			if(isColor && (n == 3 || n == 4)) {
				new Element('<input type="color" field="${p.name}">').appendTo(parent);
			}
			else {
				var row = new Element('<div class="flex"/>').appendTo(parent);
				for( i in 0...n ) {
					var e = new Element('<input type="number" field="${p.name}.$i">').appendTo(row);
					if(min == null) min = isColor ? 0.0 : -1.0;
					if(max == null)	max = 1.0;
					e.attr("min", "" + min);
					e.attr("max", "" + max);
				}
			}
		case PChoice(choices):
			var e = new Element('<select field="${p.name}" type="number"></select>').appendTo(parent);
			for(c in choices)
				new hide.Element('<option>').attr("value", choices.indexOf(c)).text(upperCase(c)).appendTo(e);
		case PEnum(en):
			var e = new Element('<select field="${p.name}"></select>').appendTo(parent);
		case PFile(exts):
			new Element('<input type="texturepath" extensions="${exts.join(" ")}" field="${p.name}">').appendTo(parent);
		case PString(len):
			var e = new Element('<input type="text" field="${p.name}">').appendTo(parent);
			if ( len != null ) e.attr("maxlength", "" + len);
			if ( p.def != null ) e.attr("value", "" + p.def);
		}
	}

	public static function makeGroupEl(name: String, content: Element) {
		var el = new Element('<div class="group" name="${name}"></div>');
		content.appendTo(el);
		return el;
	}

	public static function makeSectionEl(name: String, content: Element, ?headerContent: Element) {
		var el = new Element('<div class="section"><h1><span>${name}</span></h1><div class="content"></div></div>');
		if (headerContent != null) headerContent.appendTo(el.find("h1"));
		content.appendTo(el.find(".content"));
		return el;
	}

	public static function makeLabelEl(name: String, content: Element) {
		var el = new Element('<span><dt>${name}</dt><dd></dd></span>');
		content.appendTo(el.find("dd"));
		return el;
	}

	public static function makeListEl(content:Array<Element>) {
		var el = new Element("<dl>");
		for ( e in content ) e.appendTo(el);
		return el;
	}

	static function upperCase(prop: String) {
		return prop.charAt(0).toUpperCase() + prop.substr(1);
	}

	public static function makePropsList(props : Array<PropDef>) : Element {
		var e = new Element('<dl>');
		for( p in props ) {
			new Element('<dt>${p.disp != null ? p.disp : upperCase(p.name)}</dt>').appendTo(e);
			var def = new Element('<dd>').appendTo(e);
			makePropEl(p, def);
		}
		return e;
	}

	public function addProps( props : Array<PropDef>, context : Dynamic, ?onChange : String -> Void) {
		var e = makePropsList(props);
		return add(e, context, onChange);
	}

	public function add( e : Element, ?context : Dynamic, ?onChange : String -> Void ) {
		e.appendTo(element);
		return build(e,context,onChange);
	}

	public function build( e : Element, ?context : Dynamic, ?onChange : String -> Void ) {
		e = e.wrap("<div></div>").parent(); // necessary to have find working on top level element

		e.find("input[type=checkbox]").wrap("<div class='checkbox-wrapper'></div>");
		e.find("input[type=range]").not("[step]").attr({step: "any", tabindex:"-1"});

		// Wrap dt+dd for nw versions of 0.4x+
		for ( el in e.find("dt").wrap("<div></div>").parent().elements() ) {
			var n = el.next();
			if (n.length != 0 && n[0].tagName == "DD") n.appendTo(el);
		}

		// -- reload states ---
		for( h in e.find(".section > h1").elements() )
			if( getDisplayState("section:" + StringTools.trim(h.text())) != false )
				h.parent().addClass("open");

		// init section
		e.find(".section").not(".open").children(".content").hide();
		e.find(".section > h1").mousedown(function(e) {
			if( e.button != 0 ) return;
			var section = e.getThis().parent();
			section.toggleClass("open");
			section.children(".content").slideToggle(100);
			saveDisplayState("section:" + StringTools.trim(e.getThis().text()), section.hasClass("open"));
		}).find("input").mousedown(function(e) e.stopPropagation());

		e.find("input[type=section_name]").change(function(e) {
			e.getThis().closest(".section").find(">h1 span").text(e.getThis().val());
		});

		// init groups
		var gindex = 0;
		for( g in e.find(".group").elements() ) {
			var name = g.attr("name");
			g.wrapInner("<div class='content'></div>");
			if( name != null )
				new Element("<div class='title'>" + g.attr("name") + '</div>').prependTo(g);
			else {
				name = "_g"+(gindex++);
				g.attr("name",name);
				g.children().children(".title").prependTo(g);
			}

			var s = g.closest(".section");
			var key = (s.length == 0 ? "" : StringTools.trim(s.children("h1").text()) + "/") + name;
			if( getDisplayState("group:" + key) != false )
				g.addClass("open");
		}

		e.find(".group").not(".open").children(".content").hide();
		e.find(".group > .title").mousedown(function(e) {
			if( e.button != 0 ) return;
			var group = e.getThis().parent();
			group.toggleClass("open");
			group.children(".content").slideToggle(100);

			var s = group.closest(".section");
			var key = (s.length == 0 ? "" : StringTools.trim(s.children("h1").text()) + "/") + group.attr("name");
			saveDisplayState("group:" + key, group.hasClass("open"));

		}).find("input").mousedown(function(e) e.stopPropagation());

		e.find("input[type=group_name]").change(function(e) {
			e.getThis().closest(".group").find(">.title").val(e.getThis().val());
		});

		// init input reflection
		for( f in e.find("[field]").elements() ) {
			var f = new PropsField(this, f, context);
			f.onChange = function(undo) {
				isTempChange = f.isTempChange;
				lastChange = haxe.Timer.stamp();
				if( onChange != null ) onChange(@:privateAccess f.fname);
				isTempChange = false;
			};
			fields.push(f);

			// Init reset buttons
			var def = f.element.attr("value");
			if(def != null) {
				var dd = f.element.parent().parent("dd");
				var dt = dd.prev("dt");
				var tooltip = 'Click to reset ($def)\nCtrl+Click to round';
				var button = dt.wrapInner('<input type="button" tabindex="-1" value="${upperCase(dt.text())}" title="$tooltip"/>');
				button.click(function(e) {
					var range = @:privateAccess f.range;
					if(range != null) {
						if(e.ctrlKey) {
							range.value = Math.round(range.value);
							range.onChange(false);
						}
						else
							range.reset();
					}
				});
			}
		}
		return e;
	}

}


class PropsField extends Component {

	public var fname : String;
	public var isTempChange : Bool;
	var props : PropsEditor;
	var context : Dynamic;
	var current : Dynamic;
	var enumValue : Enum<Dynamic>;
	var tempChange : Bool;
	var beforeTempChange : { value : Dynamic };
	var tselect : hide.comp.TextureSelect;
	var fselect : hide.comp.FileSelect;
	var viewRoot : Element;
	var range : hide.comp.Range;

	public function new(props, el, context) {
		super(null,el);
		viewRoot = element.closest(".lm_content");
		this.props = props;
		this.context = context;
		var f = element;
		Reflect.setField(f[0],"propsField", this);
		fname = f.attr("field");
		current = getFieldValue();
		switch( f.attr("type") ) {
		case "checkbox":
			f.prop("checked", current);
			f.mousedown(function(e) e.stopPropagation());
			f.change(function(_) {
				undo(function() {
					var f = resolveField();
					f.current = getFieldValue();
					f.element.prop("checked", f.current);
					f.onChange(true);
				});
				current = f.prop("checked");
				setFieldValue(current);
				onChange(false);
			});
			return;
		case "texture":
			tselect = new hide.comp.TextureSelect(null,f);
			tselect.value = current;
			tselect.onChange = function() {
				undo(function() {
					var f = resolveField();
					f.current = getFieldValue();
					f.tselect.value = f.current;
					f.onChange(true);
				});
				current = tselect.value;
				setFieldValue(current);
				onChange(false);
			}
			return;
		case "texturepath":
			tselect = new hide.comp.TextureSelect(null,f);
			tselect.path = current;
			tselect.onChange = function() {
				undo(function() {
					var f = resolveField();
					f.current = getFieldValue();
					f.tselect.path = f.current;
					f.onChange(true);
				});
				current = tselect.path;
				setFieldValue(current);
				onChange(false);
			}
			return;
		case "model":
			fselect = new hide.comp.FileSelect(["hmd", "fbx"], null, f);
			fselect.path = current;
			fselect.onChange = function() {
				undo(function() {
					var f = resolveField();
					f.current = getFieldValue();
					f.fselect.path = f.current;
					f.onChange(true);
				});
				current = fselect.path;
				setFieldValue(current);
				onChange(false);
			};
			return;
		case "fileselect":
			var exts = f.attr("extensions");
			if( exts == null ) exts = "*";
			fselect = new hide.comp.FileSelect(exts.split(" "), null, f);
			fselect.path = current;
			fselect.onChange = function() {
				undo(function() {
					var f = resolveField();
					f.current = getFieldValue();
					f.fselect.path = f.current;
					f.onChange(true);
				});
				current = fselect.path;
				setFieldValue(current);
				onChange(false);
			};
			return;
		case "range":
			range = new hide.comp.Range(null,f);
			if(!Math.isNaN(current))
				range.value = current;
			range.onChange = function(temp) {
				tempChange = temp;
				setVal(range.value);
			};
			return;
		case "color":
			var arr = Std.downcast(current, Array);
			var alpha = arr != null && arr.length == 4 || f.attr("alpha") == "true";
			var picker = new hide.comp.ColorPicker(alpha, null, f);

			function updatePicker(val: Dynamic) {
				if(arr != null) {
					var v = h3d.Vector.fromArray(val);
					picker.value = v.toColor();
				}
				else if(!Math.isNaN(val))
					picker.value = val;
			}
			updatePicker(current);
			picker.onChange = function(move) {
				if(!move) {
					undo(function() {
						var f = resolveField();
						f.current = getFieldValue();
						updatePicker(f.current);
						f.onChange(true);
					});
				}
				var newVal : Dynamic =
					if(arr != null) {
						var vec = h3d.Vector.fromColor(picker.value);
						if(alpha)
							[vec.x, vec.y, vec.z, vec.w];
						else
							[vec.x, vec.y, vec.z];
					}
					else picker.value;
				if(!move)
					current = newVal;
				setFieldValue(newVal);
				onChange(false);
			};
			return;
		default:
			if( f.is("select") ) {
				enumValue = Type.getEnum(current);
				if( enumValue != null && f.find("option").length == 0 ) {
					for( c in enumValue.getConstructors() )
						new Element('<option value="$c">$c</option>').appendTo(f);
				}
			}

			if( enumValue != null ) {
				var cst = Type.enumConstructor(current);
				f.val(cst);
			} else
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

				if( f.is("[type=number]") )
					newVal = Std.parseFloat(newVal);

				if( enumValue != null )
					newVal = Type.createEnum(enumValue, newVal);

				if( f.is("select") )
					f.blur();

				setVal(newVal);
			});
		}
	}

	function getAccess() : { obj : Dynamic, index : Int, name : String } {
		var obj : Dynamic = context;
		var path = fname.split(".");
		var field = path.pop();
		for( p in path ) {
			var index = Std.parseInt(p);
			if( index != null )
				obj = obj[index];
			else
				obj = Reflect.getProperty(obj, p);
		}
		var index = Std.parseInt(field);
		if( index != null )
			return { obj : obj, index : index, name : null };
		return { obj : obj, index : -1, name : field };
	}


	function getFieldValue() {
		var a = getAccess();
		if( a.name != null )
			return Reflect.getProperty(a.obj, a.name);
		return a.obj[a.index];
	}

	function setFieldValue( value : Dynamic ) {
		var a = getAccess();
		if( a.name != null )
			Reflect.setProperty(a.obj, a.name, value);
		else
			a.obj[a.index] = value;
	}

	function undo( f : Void -> Void ) {
		var a = getAccess();
		if( a.name != null )
			props.undo.change(Field(a.obj, a.name, current), f);
		else
			props.undo.change(Array(a.obj, a.index, current), f);
	}

	function setVal(v) {
		if( current == v ) {
			// delay history save until last change
			if( tempChange || beforeTempChange == null )
				return;
			current = beforeTempChange.value;
			beforeTempChange = null;
		}
		isTempChange = tempChange;
		if( tempChange ) {
			tempChange = false;
			if( beforeTempChange == null ) beforeTempChange = { value : current };
		} else {
			undo(function() {
				var f = resolveField();
				var v = getFieldValue();
				f.current = v;
				f.element.val(v);
				f.element.parent().find("input[type=text]").val(v);
				f.onChange(true);
			});
		}
		current = v;
		setFieldValue(v);
		onChange(false);
	}

	public dynamic function onChange( wasUndo : Bool ) {
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
