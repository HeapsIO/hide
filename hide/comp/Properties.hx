package hide.comp;

class Properties extends Component {

	public var panel : Element;
	public var content : Element;
	public var undo : hide.comp.UndoHistory;

	public function new(root,?undo) {
		super(root);
		this.undo = undo == null ? new hide.comp.UndoHistory() : undo;
		var e = new Element("<div class='hide-properties'><div class='content'></div><div class='panel'></div></div>").appendTo(root);
		content = e.find(".content");
		panel = e.find(".panel");
	}

	public function add( e : Element, context : Dynamic ) {

		e.appendTo(panel);
		e = e.wrap("<div></div>").parent(); // necessary to have find working on top level element

		e.find("input[type=checkbox]").wrap("<div class='checkbox-wrapper'></div>");

		e.find("input[type=range]").not("[step]").attr("step", "any");

		e.find(".section").not(".open").children(".content").hide();
		e.find(".section > h1").mousedown(function(e) {
			if( e.button != 0 ) return;
			var section = js.jquery.Helper.JTHIS.parent();
			section.toggleClass("open");
			section.children(".content").slideToggle(100);
		}).find("input").mousedown(function(e) e.stopPropagation());

		for( g in e.find(".group").elements() ) {
			g.wrapInner("<div class='content'></div>'");
			if( g.attr("name") != null ) new Element("<div class='title'>" + g.attr("name") + '</div>').prependTo(g);
		}

		e.find(".group > .title").mousedown(function(e) {
			if( e.button != 0 ) return;
			var group = js.jquery.Helper.JTHIS.parent();
			group.children(".content").slideToggle(100);
		}).find("input").mousedown(function(e) e.stopPropagation());

		for( f in e.find("[field]").elements() ) {
			var fname = f.attr("field");
			var current : Dynamic = Reflect.field(context, fname);
			var enumValue : Enum<Dynamic> = null;
			var tempChange = false;
			var hadTempChange = false;

			switch( f.attr("type") ) {
			case "checkbox":
				f.prop("checked", current);
				f.change(function(_) {
					undo.change(Field(context, fname, current), function() {
						current = Reflect.field(context, fname);
						f.prop("checked", current);
					});
					current = f.prop("checked");
					Reflect.setProperty(context, fname, current);
				});
				continue;
			case "texture":
				var sel = new hide.comp.TextureSelect(f);
				sel.value = current;
				sel.onChange = function() {
					undo.change(Field(context, fname, current), function() {
						current = Reflect.field(context, fname);
						sel.value = current;
					});
					current = sel.value;
					Reflect.setProperty(context, fname, current);
				}
				continue;
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
					if( tempChange || !hadTempChange )
						return;
					hadTempChange = false;
				}

				if( tempChange ) {
					tempChange = false;
					hadTempChange = true;
				}
				else {
					undo.change(Field(context, fname, current), function() {
						current = Reflect.field(context, fname);
						f.val(current);
					});
				}
				current = newVal;
				Reflect.setProperty(context, fname, newVal);

			});
		}

	}

}