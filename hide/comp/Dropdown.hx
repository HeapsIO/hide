package hide.comp;

typedef Choice = {
	var id: String;
	var text: String;
	@:optional var ico: Dynamic;
	@:optional var classes: Array<String>;
	@:optional var doc: String;
}

class Dropdown extends Component {
	var highlightIndex : Null<Int> = null;
	var optionsCont : Element;
	public var filterInput : Element;
	var options : Array<Choice>;

	public function new( parent, options : Array<Choice>, currentValue: String, ?buildIcon : (Choice) -> Element ) {
		var root = new Element('<div class="hide-dropdown">
			<div class="dropdown-cont">
				<input id="filter" class="filter-input" type="text"/>
				<div class="options"></div>
			</div>
		</div>');
		this.options = options;
		filterInput = root.find("#filter").first();

		optionsCont = root.find(".options").first();
		for( i in 0...options.length ) {
			var o = options[i];
			var el = new Element('<div tabindex="-1" class="dropdown-option">
				<p class="option-text">${StringTools.htmlEscape(o.text)}</p>
			</div>');
			if( buildIcon != null )
				el.prepend(buildIcon(o));
			if( o.id == currentValue )
				el.addClass("current-value");
			if( o.classes != null ) {
				for( c in o.classes )
					el.addClass(c);
			}
			if( o.doc != null && o.doc != "" ) {
				el.attr("title", o.doc);
				new Element('<i style="margin-left: 5px" class="ico ico-book"/>').appendTo(el.find(".option-text"));
			}
			el.data("id", o.id);
			el.data("text", o.text);
			el.click((_) -> applyValue(o.id));
			el.mousemove(function(_) {
				highlightIndex = i;
				refreshHighlight();
			});
			optionsCont.append(el);
		}

		filterInput.on("input", (e : js.jquery.Event) -> {
			var v = filterInput.val();
			if (v != null) {
				for( o in optionsCont.children().elements() ) {
					o.toggleClass("hidden", !matches(o.data("text"), v) && !matches(o.data("id"), v));
				}
			}
			resetHighlight();
		});
		filterInput.keydown(onKey);
		resetHighlight();

		super(parent, root);
		var pos = element.offset();
		var window = js.Browser.window;
		var cont = element.find(".dropdown-cont").first();
		if (pos.top + cont.outerHeight() > window.innerHeight && pos.top - cont.outerHeight() >= 0) {
			cont.css("top", -cont.outerHeight());
			filterInput.on("input", function(_) {
				cont.css("top", -cont.outerHeight());
			});
		}
		filterInput.focus();

		filterInput.blur(function(e) {
			if( e.relatedTarget != null && new Element(e.relatedTarget).hasClass("dropdown-option") )
				return;
			if( !removed && element[0].isConnected )
				remove();
		});

	}

	var removed = false;
	override function remove() {
		super.remove();
		removed = true;
		onClose();
	}

	function resetHighlight() {
		if( optionsCont.length == 0 ) {
			highlightIndex = null;
			return;
		} else {
			var i = 0;
			for( o in optionsCont.children().elements() ) {
				if ( !o.hasClass("hidden") ) {
					highlightIndex = i;
					break;
				}
				i++;
			}
		}
		refreshHighlight();
	}

	function refreshHighlight() {
		var i = 0;
		for( o in optionsCont.children().elements() ) {
			o.toggleClass("highlighted", i == highlightIndex);
			i++;
		}
		untyped optionsCont.children().get(highlightIndex).scrollIntoViewIfNeeded();
	}

	function matches( text : String, filter : String ) {
		if (text == null || filter == null)
			return false;
		text = text.toLowerCase();
		filter = filter.toLowerCase();
		if( text.indexOf(filter) >= 0 )
			return true;
		text.split("_").join("").split(" ").join("");
		filter.split(" ").join("");
		if( text.indexOf(filter) >= 0 )
			return true;
		return false;
	}

	function onKey( e : js.jquery.Event ) {
		if( e.altKey )
			return true;
		var children = optionsCont.children();
		switch( e.keyCode ) {
			case hxd.Key.UP:
				var i = highlightIndex - 1;
				while( i >= 0 ) {
					if( !new Element(children.get(i)).hasClass("hidden") ) {
						highlightIndex = i;
						refreshHighlight();
						break;
					}
					i--;
				}
				return false;
			case hxd.Key.DOWN:
				var i = highlightIndex + 1;
				while( i < options.length ) {
					if( !new Element(children.get(i)).hasClass("hidden") ) {
						highlightIndex = i;
						refreshHighlight();
						break;
					}
					i++;
				}
				return false;
			case hxd.Key.PGUP:
				resetHighlight();
				return false;
			case hxd.Key.PGDOWN:
				var i = options.length - 1;
				while( i >= 0 ) {
					if( !new Element(children.get(i)).hasClass("hidden") ) {
						highlightIndex = i;
						refreshHighlight();
						break;
					}
					i--;
				}
				return false;
			case hxd.Key.ENTER:
				if (highlightIndex != null) {
 					applyValue(options[highlightIndex].id);
					return false;
				}
			case hxd.Key.ESCAPE:
				remove();
				return false;
		}
		return true;
	}

	function applyValue(val: String) {
		onSelect(val);
		remove();
	}

	public dynamic function onSelect(val: String) {}
	public dynamic function onClose() {}
}