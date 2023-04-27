package hide.comp;
using hide.tools.Extensions;

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
	public var ignoreIdInSearch : Bool = false; // Search won't filter based on id if this is true
	public var filterInput : Element;
	var options : Array<Choice>;
	var orderedOptions : Array<Choice>;
	var anchor : Element = null;

	public function new( parent, options : Array<Choice>, currentValue: String, ?buildIcon : (Choice) -> Element, detached : Bool = false ) {
		var root = new Element('<div class="hide-dropdown">
			<div class="dropdown-cont">
				<input id="filter" autocomplete="off" class="filter-input" type="text"/>
				<div class="options"></div>
			</div>
		</div>');
		this.options = options;
		this.orderedOptions = options.copy();
		filterInput = root.find("#filter").first();

		optionsCont = root.find(".options").first();
		for( o in options ) {
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
				highlightIndex = orderedOptions.indexOf(o);
				refreshHighlight();
			});
			optionsCont.append(el);
		}

		function sorter(t1, id1, t2, id2, filter: String) {
			var m1 = getMatchingScore(t1, filter);
			var m2 = getMatchingScore(t2, filter);
			if (m1 != m2)
				return m1 - m2;
			return options.findIndex(o -> o.id == id1) - options.findIndex(o -> o.id == id2);
		}

		filterInput.on("input", (e : js.jquery.Event) -> {
			var v = filterInput.val();
			if (v != null) {
				for( o in optionsCont.children().elements() ) {
					var m = matches(o.data("text"), v) || (!ignoreIdInSearch && matches(o.data("id"), v));
					o.toggleClass("hidden", !m);
				}
				var sortedChildren = optionsCont.children().elements().toArray();
				sortedChildren.sort((a, b) -> sorter(a.data("text"), a.data("id"), b.data("text"), b.data("id"), v));
				orderedOptions.sort((a, b) -> sorter(a.text, a.id, b.text, b.id, v));
				optionsCont.append(sortedChildren);
			}
			resetHighlight();
		});
		filterInput.keydown(onKey);
		resetHighlight();

		if (!detached) {
			super(parent, root);
		}
		else {
			var body = root.closest(".lm_content");
			if (body.length == 0) body = new Element("body");
			anchor = parent;
			super(body, root);

			root.width(anchor.get(0).offsetWidth);
			reflow();

			var timer = new haxe.Timer(500);
			timer.run = function() {
				if( anchor.closest("body").length == 0 ) {
					timer.stop();
					remove();
				}
			};
		}
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

	function reflow() {
		var offset = anchor.offset();
		var popupHeight = element.get(0).offsetHeight;
		var popupWidth = element.get(0).offsetWidth;

		var clientHeight = js.Browser.document.documentElement.clientHeight;
		var clientWidth = js.Browser.document.documentElement.clientWidth;

		offset.top += anchor.get(0).offsetHeight;
		offset.top = Math.min(offset.top,  clientHeight - popupHeight - 32);

		//offset.left += anchor.get(0).offsetWidth;
		offset.left = Math.min(offset.left,  clientWidth - popupWidth - 32);

		element.offset(offset);
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

	function getMatchingScore( text : String, filter : String ) {
		if (text == null || filter == null)
			return -1;
		text = text.toLowerCase();
		filter = filter.toLowerCase();
		var i = text.indexOf(filter);
		if( i >= 0 )
			return i;
		text.split("_").join("").split(" ").join("");
		filter.split(" ").join("");
		i = text.indexOf(filter);
		if( i >= 0 )
			return i;
		return -1;
	}

	function matches( text : String, filter : String ) {
		return getMatchingScore(text, filter) >= 0;
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
 					applyValue(orderedOptions[highlightIndex].id);
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