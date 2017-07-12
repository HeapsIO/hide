package hide.comp;

class Properties extends Component {

	public var panel : Element;
	public var content : Element;

	public function new(root) {
		super(root);
		var e = new Element("<div class='hide-properties'><div class='content'></div><div class='panel'></div></div>").appendTo(root);
		content = e.find(".content");
		panel = e.find(".panel");
	}

	public dynamic function beforeChange() {
	}

	public function add( e : Element, context : Dynamic ) {

		e.appendTo(panel);
		e = e.wrap("<div></div>").parent(); // necessary to have find working on top level element

		e.find("input[type=checkbox]").wrap("<div class='checkbox-wrapper'></div>");

		e.find("input[type=range]").not("[step]").attr("step", "any");

		e.find(".section").not(".open").find(".content").hide();
		e.find(".section > h1").mousedown(function(e) {
			if( e.button != 0 ) return;
			var section = js.jquery.Helper.JTHIS.parent();
			section.toggleClass("open");
			section.children(".content").toggle(100);
		}).find("input").mousedown(function(e) e.stopPropagation());

		for( f in e.find("[field]").elements() ) {
			var fname = f.attr("field");
			var current : Dynamic = Reflect.field(context, fname);
			var enumValue : Enum<Dynamic> = null;
			if( f.attr("type") == "checkbox" ) {
				f.prop("checked", current);
				f.change(function(_) {
					beforeChange();
					Reflect.setProperty(context, fname, f.prop("checked"));
				});
				continue;
			}

			if( f.is("select") ) {
				enumValue = Type.getEnum(current);
				if( enumValue != null && f.find("option").length == 0 ) {
					for( c in enumValue.getConstructors() )
						new Element('<option value="$c">$c</option>').appendTo(f);
				}
			}

			if( f.is("[type=range]") )
				f.on("input", function(_) f.change());

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
				f.change();
			});
			f.change(function(e) {

				var newVal : Dynamic = f.val();

				if( f.is("[type=range]") )
					newVal = Std.parseFloat(newVal);

				if( enumValue != null )
					newVal = Type.createEnum(enumValue, newVal);

				if( current == newVal ) return;

				beforeChange();
				trace(fname, newVal, Type.typeof(newVal));
				current = newVal;
				Reflect.setProperty(context, fname, newVal);
			});
		}

	}

}