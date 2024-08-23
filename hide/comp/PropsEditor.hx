package hide.comp;
import hide.comp.GradientEditor.GradientBox;
import hrt.impl.TextureType.Utils;
import hrt.prefab.Props;

using hrt.tools.MapUtils;


class PropsEditor extends Component {

	public var undo : hide.ui.UndoHistory;
	public var lastChange : Float = 0.;
	public var fields(default, null) : Array<PropsField>;
	public var groups(default, null) : Map<String, Array<PropsField>>;
	public var currentEditContext : hide.prefab.EditContext = null;
	public var hashToContextes : Map<String, Array<{context: Dynamic, onChange: String -> Void}>>;

	public var isTempChange = false;

	public function new(?undo,?parent,?el) {
		super(parent,el);
		element.addClass("hide-properties");
		this.undo = undo == null ? new hide.ui.UndoHistory() : undo;
		fields = [];
		groups = new Map();
	}

	public function clear() {
		element.empty();
		fields = [];
		groups = new Map();
		hashToContextes = [];
	}

	public function onDragDrop( items : Array<String>, isDrop : Bool ) : Bool {
		if( items.length == 0 )
			return false;

		var pickedEl = js.Browser.document.elementFromPoint(ide.mouseX, ide.mouseY);
		var rootEl = element[0];
		while( pickedEl != null ) {
			if( pickedEl == rootEl )
				return false;
			for( field in fields ) {
				if( field.tselect != null && field.tselect.element[0] == pickedEl )
					return field.tselect.onDragDrop(items, isDrop);
				if( field.fselect != null && field.fselect.element[0] == pickedEl )
					return field.fselect.onDragDrop(items, isDrop);
			}
			pickedEl = pickedEl.parentElement;
		}
		return false;
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
		case PTexturePath:
			new Element('<input type="texturepath" field="${p.name}">').appendTo(parent);
		case PTexture:
			new Element('<input type="texturechoice" field="${p.name}">').appendTo(parent);
		case PColor:
			new Element('<input type="color" field="${p.name}">').appendTo(parent);
		case PGradient:
			new Element('<input type="gradient" field="${p.name}">').appendTo(parent);
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
					var e = new Element('<input type="number" field="${p.name}.$i" step="0.1">').appendTo(row);
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

	public static function getCategory(p: PropDef) {
		if (p.name != null) {
			return p.name.split("_")[0];
		}
		return null;
	}

	public static function makePropsList(props : Array<PropDef>) : Element {
		var e = new Element('<dl>');
		var currentParent = e;
		var currentCategory = null;
		for(i => p in props ) {
			var name = p.disp != null ? p.disp : upperCase(p.name);

			name = StringTools.replace(name, "_", " ");
			var finalName = new StringBuf();
			var prevWasSpace = true;
			for (i => n in StringTools.keyValueIterator(name)) {
				var c = StringTools.fastCodeAt(name, i);
				if (c >= 65 && c <= 90 && !prevWasSpace) {
					finalName.addChar(8203); // Zero width space;
				}
				prevWasSpace = c == 32;
				finalName.addChar(c);
			}

			name = finalName.toString();

			new Element('<dt>$name</dt>').appendTo(currentParent);
			var def = new Element('<dd>').appendTo(currentParent);
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
        var hash = getBuildLocationHash();
		var contextes = hashToContextes.getOrPut(hash, []);
		contextes.push({context: context, onChange: onChange});
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
			if( getDisplayState("group:" + key) != false && !g.hasClass("closed") )
				g.addClass("open");

			var groupName = g.attr("name");
			groups.set(groupName, []);
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
		for( field in e.find("[field]").elements() ) {
			var f = new PropsField(this, field, hash);
			f.onChange = function(undo) {
				isTempChange = f.isTempChange;
				lastChange = haxe.Timer.stamp();
				for (context in contextes) {
					if (context.onChange != null) {
						context.onChange(@:privateAccess f.fname);
					}
				}
				isTempChange = false;
			};
			var groupName = f.element.closest(".group").attr("name");
			if (groupName != null) {
				groups.get(groupName).push(f);
			}
			fields.push(f);
			// Init reset buttons
			var def = f.element.attr("value");
			if(def != null) {
				var dd = f.element.parent().parent("dd");
				wrapDt(dd.prev("dt"), def, function(e) {
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

	/**
		Returns a string that tries to be unique for each call of properties.add or properties.build
		inside a prefab.edit function.
	**/
	static function getBuildLocationHash() : String {
		var callStack = haxe.CallStack.callStack();
		var len = callStack.length;

		var lastEditIndex = 0;
		for (idx in 0...len) {
			var i = idx;
			var stackItem = callStack[i];
			switch (stackItem) {
				case FilePos(subStack, file, line, column):
					switch(subStack) {
						case Method(_, "edit"):
							lastEditIndex = i;
							break;
						case Method(_, _):
							// do nothing
						case null:
						default:
							throw "unkown";
					}
				default:
					throw "unkown";
			}
		}

		var hash = "";
		for (idx in 0...lastEditIndex) {
			var i = lastEditIndex - idx;
			var stackItem = callStack[i];
			switch (stackItem) {
				case FilePos(subStack, file, line, column):
					switch(subStack) {
						case Method(_, name) :
							switch (name) {
								case "add" | "build":
									break;
								default:
							}
							hash += '$name:$line:$column,';
						case null:
							hash += 'null:$line:$column,';
						default:
					}
				default:
					throw "unknown";
			}
		}
		return hash;
	}

	public static function wrapDt(dt : Element, defValue : String, onClick : (e : js.jquery.Event) -> Void) {
		var tooltip = 'Click to reset ($defValue)\nCtrl+Click to round';
		var button = dt.wrapInner('<input type="button" tabindex="-1" value="${upperCase(dt.text())}" title="$tooltip"/>');
		button.click(onClick);
	}

}


@:allow(hide.comp.PropsEditor)
class PropsField extends Component {
	public var fname : String;
	var isTempChange : Bool;
	var props : PropsEditor;
	var locationHash : String;
	var currents : Array<Dynamic>;
	var currentSave : Array<Dynamic>;

	var enumValue : Enum<Dynamic>;
	var tempChange : Bool;
	var beforeTempChange : Array<Dynamic>;
	var tchoice : hide.comp.TextureChoice;
	var gradient : GradientBox;
	var multiRange : MultiRange;
	var tselect : hide.comp.TextureSelect;
	var fselect : hide.comp.FileSelect;
	var viewRoot : Element;
	var range : hide.comp.Range;

	var subfields : Array<String>;

	public function new(props, el, hash) {
		super(null,el);
		locationHash = hash;
		viewRoot = element.closest(".lm_content");
		this.props = props;
		var f = element;
		Reflect.setField(f[0],"propsField", this);
		fname = f.attr("field");
		currents = getFieldValues();
		switch( f.attr("type") ) {
		case "checkbox":
			f.prop("checked", currents[0]);
			f.mousedown(function(e) e.stopPropagation());
			f.change(function(_) {
				undo(function() {
					var f = resolveField();
					f.currents = getFieldValues();
					f.element.prop("checked", f.currents[0]);
					f.onChange(true);
				});
				currents = valToValues(f.prop("checked"));
				setFieldValues(currents);
				onChange(false);
			});
			return;
		case "texture":
			tselect = new hide.comp.TextureSelect(null,f);
			tselect.value = currents[0];
			tselect.onChange = function() {
				undo(function() {
					var f = resolveField();
					f.currents = getFieldValues();
					f.tselect.value = f.currents[0];
					f.onChange(true);
				});
				currents = valToValues(tselect.value);
				setFieldValues(currents);
				onChange(false);
			}
			return;
		case "texturepath":
			tselect = new hide.comp.TextureSelect(null,f);
			tselect.path = currents[0];
			tselect.onChange = function() {
				undo(function() {
					var f = resolveField();
					f.currents = getFieldValues();
					f.tselect.path = f.currents[0];
					f.onChange(true);
				});
				currents = valToValues(tselect.path);
				setFieldValues(currents);
				onChange(false);
			}
			return;
		case "texturechoice":
			tchoice = new TextureChoice(null, f);
			tchoice.value = currents[0];
			currentSave = [for (current in currents) Utils.copyTextureData(current)];

			tchoice.onChange = function(shouldUndo : Bool) {

				if (shouldUndo) {
					var setVals = function(vals, undo) {
						var f = resolveField();
						f.currents = vals;
						f.currentSave = [for (current in vals) Utils.copyTextureData(current)];
						f.tchoice.value = vals[0];
						setFieldValues(vals);
						f.onChange(undo);
					}

					var oldVal = [for (current in currentSave) Utils.copyTextureData(current)];
					var newVal = valToValues(Utils.copyTextureData(tchoice.value));

					props.undo.change(Custom(function(undo) {
						if (undo) {
							setVals(oldVal, true);
						} else {
							setVals(newVal, false);
						}
					}));

					setVals(valToValues(tchoice.value), false);
				} else {
					currents = valToValues(Utils.copyTextureData(tchoice.value));
					setFieldValues(currents);
					onChange(false);
				}
			}
			return;
		case "gradient":
			gradient = new GradientBox(null, f);
			gradient.value = currents[0];
			currentSave = [for (grad in currents) Utils.copyTextureData(grad)];

			gradient.onChange = function(shouldUndo : Bool) {
				if (shouldUndo) {
					var setVals = function(vals, undo) {
						var f = resolveField();
						f.currents = vals;
						f.currentSave = [for (grad in vals) Utils.copyTextureData(grad)];
						f.gradient.value = vals[0];
						setFieldValues(vals);
						f.onChange(undo);
					}

					var oldVal = [for (grad in currentSave) Utils.copyTextureData(grad)];
					var newVal = valToValues(Utils.copyTextureData(gradient.value));

					props.undo.change(Custom(function(undo) {
						if (undo) {
							setVals(oldVal, true);
						} else {
							setVals(newVal, false);
						}
					}));

					setVals(valToValues(gradient.value), false);
				} else {
					currents = valToValues(gradient.value);
					setFieldValues(currents);
					onChange(false);
				}
			}
		case "model":
			fselect = new hide.comp.FileSelect(["hmd", "fbx"], null, f);
			fselect.path = currents[0];
			fselect.onChange = function() {
				undo(function() {
					var f = resolveField();
					f.currents = getFieldValues();
					f.fselect.path = f.currents[0];
					f.onChange(true);
				});
				currents = valToValues(fselect.path);
				setFieldValues(currents);
				onChange(false);
			};
			return;
		case "fileselect":
			var exts = f.attr("extensions");
			if( exts == null ) exts = "*";
			fselect = new hide.comp.FileSelect(exts.split(" "), null, f);
			fselect.path = currents[0];
			fselect.onChange = function() {
				undo(function() {
					var f = resolveField();
					f.currents = getFieldValues();
					f.fselect.path = f.currents[0];
					f.onChange(true);
				});
				currents = valToValues(fselect.path);
				setFieldValues(currents);
				onChange(false);
			};
			return;
		case "range":
			range = new hide.comp.Range(null,f);
			if(!Math.isNaN(currents[0]))
				range.value = currents[0];
			range.onChange = function(temp) {
				tempChange = temp;
				setVal(range.value);
			};
			return;
		case "multi-range":
			var subfieldStr = f.attr("data-subfields");
			subfields = subfieldStr.split(",");

			var name = f.parent().prev("dt").text();
			var parentDiv = f.parent().parent();
			parentDiv.empty();

			var multiRange = new hide.comp.MultiRange(parentDiv, f, subfields.length, [for (subfield in subfields) name + " " + subfield]);
			var a = getAccess();
			currents = getFieldValues();
			multiRange.value = currents[0];

			currentSave = [for (c in currents)(cast c:Array<Float>).copy()];
			multiRange.onChange = function(isTemporary : Bool) {
				var setVals = function(vals : Array<Array<Float>>, undo, refreshComp) {
					var f = resolveField();
					var a = f.getAccess();
					setFieldValues(vals);
					f.currents = getFieldValues();
					f.currentSave = [for (c in f.currents) (cast c:Array<Float>).copy()];
					if (refreshComp)
						multiRange.value = vals[0];
					f.onChange(undo);
				};

				if (!isTemporary) {
					var arr : Array<Array<Float>> = cast currentSave;
					var oldVal = arr.copy();
					var newVal = multiRange.value.copy();

					props.undo.change(Custom(function(undo) {
						if (undo) {
							setVals(oldVal, true, true);
						} else {
							setVals(cast valToValues(newVal), false, true);
						}
					}));
					setVals(cast valToValues(multiRange.value), false, false);
				}
				else {
					var a = getAccess();
					var val = multiRange.value;
					currents = valToValues(val);
					setFieldValues(currents);
					onChange(false);
				}
			};
		case "color":
			var arr = Std.downcast(currents[0], Array);
			var alpha = arr != null && arr.length == 4 || f.attr("alpha") == "true";
			var picker = new hide.comp.ColorPicker.ColorBox(null, f, true, alpha, fname);
			element = picker.element;
			function updatePicker(val: Dynamic) {
				if(arr != null) {
					var v = h3d.Vector.fromArray(val);
					picker.value = v.toColor();
				}
				else if(!Math.isNaN(val))
					picker.value = val;
			}
			updatePicker(currents[0]);
			picker.onChange = function(move) {
				isTempChange = move;
				if(!move) {
					undo(function() {
						var f = resolveField();
						f.currents = getFieldValues();
						updatePicker(f.currents[0]);
						f.onChange(true);
					});
				}
				var newVal : Dynamic =
					if(arr != null) {
						var vec = h3d.Vector4.fromColor(picker.value);
						if(alpha)
							[vec.x, vec.y, vec.z, vec.w];
						else
							[vec.x, vec.y, vec.z];
					}
					else picker.value;
				if(!move)
					currents = valToValues(newVal);
				setFieldValues(valToValues(newVal));
				onChange(false);
			};
			return;
		case "custom":
			return;
		default:
			if( f.is("select") ) {
				enumValue = Type.getEnum(currents[0]);
				if( enumValue != null && f.find("option").length == 0 ) {
					var meta = haxe.rtti.Meta.getFields(enumValue);
					for( c in enumValue.getConstructors() ) {

						var name = c;
						var comment = "";
						if (Reflect.hasField(meta, c)) {
							var fieldMeta = Reflect.getProperty(meta, c);
							if (Reflect.hasField(fieldMeta, "display")) {
								var displayArr = Reflect.getProperty(fieldMeta, "display");
								if (displayArr.length > 0) {
									name = displayArr[0];
								}
								if (displayArr.length > 1) {
									comment = displayArr[1];
								}
							}
						}

						new Element('<option value="$c" title="$comment">$name</option>').appendTo(f);
					}
				}
			}

			if( enumValue != null ) {
				var cst = Type.enumConstructor(currents[0]);
				f.val(cst);
			} else
				f.val(currents[0]);
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

	public function valToValues(val: Dynamic) : Array<Dynamic> {
		return [for (_ in getContextes()) val];
	}

	function getContextes() {
		return props.hashToContextes.get(locationHash);
	}

	function getAccess() : { objs : Array<Dynamic>, index : Int, name : String } {
		var objs : Array<Dynamic> = [for (c in getContextes()) c.context];
		var path = fname.split(".");
		var field = path.pop();
		for( p in path ) {
			var index = Std.parseInt(p);
			if( index != null )
				objs = [for (obj in objs) obj[index]];
			else
				objs = [for (obj in objs) Reflect.getProperty(obj, p)];
		}
		var index = Std.parseInt(field);
		if( index != null )
			return { objs : objs, index : index, name : null };
		return { objs : objs, index : -1, name : field };
	}

	function getAccesses() : Array<{ objs : Array<Dynamic>, index : Int, name : String }> {
		if (subfields == null)
			return [getAccess()];
		return [
			for (subfield in subfields) {
				var a = getAccess();
				a.name = a.name + subfield;
				a;
			}
		];
	}


	function getFieldValues() : Array<Dynamic> {
		var a = getAccess();
		if( a.name != null )
			return [for (obj in a.objs) Reflect.getProperty(obj, a.name)];
		return [for (obj in a.objs) obj[a.index]];
	}

	// function setFieldValue( value : Dynamic ) {
	// 	var a = getAccess();

	// 	if (a.objs == null)
	// 		return;

	// 	if( a.name != null ) {
	// 		for (obj in a.objs) {
	// 			Reflect.setProperty(obj, a.name, value);
	// 		}
	// 	}
	// 	else {
	// 		for (obj in a.objs) {
	// 			obj[a.index] = value;
	// 		}
	// 	}
	// }

	function setFieldValues(values : Array<Dynamic>) {
		var a = getAccess();

		if (a.objs == null)
			return;

		if( a.name != null ) {
			for (i => obj in a.objs) {
				Reflect.setProperty(obj, a.name, values[i]);
			}
		}
		else {
			for (i => obj in a.objs) {
				obj[a.index] = values[i];
			}
		}
	}

	function undo( f : Void -> Void ) {
		var a = getAccess();
		var undo = new hide.ui.UndoHistory();
		for (i => obj in a.objs) {
			if( a.name != null ) {
				undo.change(Field(obj, a.name, currents[i]));
			}
			else {
				undo.change(Array(obj, a.index, currents[i]));
			}
		}

		var exec = function(isUndo: Bool) {
			if (isUndo) {
				while(undo.undo()) {};
			} else {
				while(undo.redo()) {};
			}
			f();
		}

		props.undo.change(Custom(exec));
	}

	function setVal(v) {
		if( currents[0] == v ) {
			// delay history save until last change
			if( tempChange || beforeTempChange == null )
				return;
			currents = beforeTempChange;
			beforeTempChange = null;
		}
		isTempChange = tempChange;
		if( tempChange ) {
			tempChange = false;
			if( beforeTempChange == null ) beforeTempChange = haxe.Json.parse(haxe.Json.stringify(currents));
		} else {
			undo(function() {
				var f = resolveField();
				var v = getFieldValues();
				f.currents = v;
				f.element.val(v[0]);
				f.element.parent().find("input[type=text]").val(v[0]);
				f.onChange(true);
			});
		}
		currents = valToValues(v);
		setFieldValues(valToValues(v));
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
			if( p != null && p.locationHash == locationHash && p.fname == fname )
				return p;
		}

		return this;
	}

}
