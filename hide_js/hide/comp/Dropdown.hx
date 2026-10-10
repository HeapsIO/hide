package hide.comp;
using hide.tools.Extensions;

typedef Choice = {
	var id: String;
	var text: String;
	@:optional var ico: Dynamic;
	@:optional var classes: Array<String>;
	@:optional var doc: String;
	@:optional var index: Int;
	@:optional var searchText: String;
}

/**
	A list of choices with a filter. The list is virtual : only the options in its view are in the DOM.
**/
class Dropdown extends Component {
	// index in `visible`
	var highlightIndex : Null<Int> = null;
	var optionsCont : Element;
	public var ignoreIdInSearch : Bool = false; // Search won't filter based on id if this is true
	public var filterInput : Element;
	var options : Array<Choice>;
	// the options matching the filter, sorted
	var visible : Array<Choice>;
	var currentValue : String;
	var buildIcon : Choice -> Element;
	var anchor : Element = null;
	var timer : haxe.Timer;
	#if js
	var sizer : js.html.Element;
	var optionElements : Map<Int, js.html.Element> = new Map();
	var rendered : Array<js.html.Element> = [];
	var itemHeight = 30.;
	#end


	public function new( parent, options : Array<Choice>, currentValue: String, ?buildIcon : (Choice) -> Element, detached : Bool = false ) {
		var root = new Element('<div class="hide-dropdown">
			<div class="dropdown-cont">
				<input id="filter" autocomplete="off" class="filter-input" type="text"/>
				<div class="options"></div>
			</div>
		</div>');
		this.options = options;
		this.currentValue = currentValue;
		this.buildIcon = buildIcon;
		for( i in 0...options.length ) {
			options[i].index = i;
			if( options[i].id == currentValue && highlightIndex == null )
				highlightIndex = i;
		}
		this.visible = options.copy();
		filterInput = root.find("#filter").first();
		#if js
		optionsCont = root.find(".options").first();
		sizer = js.Browser.document.createDivElement();
		sizer.className = "options-sizer";
		optionsCont.get(0).appendChild(sizer);
		optionsCont.on("scroll", (_) -> renderOptions());

		filterInput.on("input", (e : Element.Event) -> {
			var v = filterInput.val();
			if (v != null) {
				visible = [for( o in options ) if( matches(o.text, v) || (!ignoreIdInSearch && matches(o.id, v)) || matches(o.searchText, v) ) o];
				visible.sort((a, b) -> {
					var m1 = getMatchingScore(a.text, v);
					var m2 = getMatchingScore(b.text, v);
					return m1 != m2 ? m1 - m2 : a.index - b.index;
				});
				optionsCont.get(0).scrollTop = 0;
				renderOptions();
			}
			resetHighlight();
		});
		filterInput.keydown(onKey);

		if (!detached) {
			super(parent, root);
		}
		else {
			var body = root.closest(".lm_content");
			if (body.length == 0) body = new Element("body");
			anchor = parent;
			super(body, root);
		}
		renderOptions();
		if( detached ) {
			root.width(anchor.get(0).offsetWidth);
			reflow();

			timer = new haxe.Timer(500);
			timer.run = function() {
				if( anchor.closest("body").length == 0 ) {
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

		refreshHighlight();

		#else
		super(parent, root);
		#end
	}

	#if js
	function reflow() {
		var offset = anchor.offset();
		var popupHeight =  element.get(0).offsetHeight;
		var popupWidth = hxd.Math.clamp(element.get(0).offsetWidth, 300, 600);

		var clientHeight = js.Browser.document.documentElement.clientHeight;
		var clientWidth = js.Browser.document.documentElement.clientWidth;

		offset.top += anchor.get(0).offsetHeight;
		offset.top = Math.min(offset.top,  clientHeight - popupHeight - 8);

		//offset.left += anchor.get(0).offsetWidth;
		offset.left = Math.min(offset.left,  clientWidth - popupWidth - 8);

		element.offset(offset);
		element.width(popupWidth);
	}

	function getOptionElement( o : Choice ) {
		var e = optionElements.get(o.index);
		if( e != null )
			return e;
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
		el.click((_) -> applyValue(o.id));
		el.mousemove(function(_) {
			var i = visible.indexOf(o);
			if( i == highlightIndex ) return;
			highlightIndex = i;
			refreshHighlight(false);
		});
		e = el.get(0);
		optionElements.set(o.index, e);
		return e;
	}

	/**
		Puts in the DOM the options which are in the view of the list.
	**/
	function renderOptions() {
		var cont = optionsCont.get(0);
		for( pass in 0...2 ) {
			sizer.style.height = (visible.length * itemHeight) + "px";
			var first = Std.int(Math.max(0, Math.floor(cont.scrollTop / itemHeight) - 5));
			var last = Std.int(Math.min(visible.length, Math.ceil((cont.scrollTop + Math.max(cont.clientHeight, 200)) / itemHeight) + 5));
			var shown = [];
			for( i in first...last ) {
				var e = getOptionElement(visible[i]);
				e.style.top = (i * itemHeight) + "px";
				e.classList.toggle("highlighted", i == highlightIndex);
				if( e.parentNode != sizer )
					sizer.appendChild(e);
				shown.push(e);
			}
			for( e in rendered )
				if( shown.indexOf(e) < 0 && e.parentNode != null )
					e.parentNode.removeChild(e);
			rendered = shown;
			// the options have the height of the first one (with its icon)
			if( shown.length == 0 || shown[0].offsetHeight <= 0 || shown[0].offsetHeight == itemHeight )
				break;
			itemHeight = shown[0].offsetHeight;
		}
	}
	#end

	var removed = false;
	override function remove() {
		super.remove();
		if (removed == false) {
			if (timer != null)
				timer.stop();
			removed = true;
			onClose();
		}
	}

	function resetHighlight() {
		highlightIndex = visible.length == 0 ? null : 0;
		refreshHighlight();
	}

	function refreshHighlight( scroll = true ) {
		#if js
		if( highlightIndex != null && scroll ) {
			// scroll the list to show the highlighted option
			var cont = optionsCont.get(0);
			var top = highlightIndex * itemHeight;
			if( top < cont.scrollTop )
				cont.scrollTop = Std.int(top);
			else if( top + itemHeight > cont.scrollTop + cont.clientHeight )
				cont.scrollTop = Std.int(top + itemHeight - cont.clientHeight);
		}
		renderOptions();
		#end
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

	function onKey( e : Element.Event ) {
		if( e.altKey )
			return true;
		switch( e.keyCode ) {
			case hxd.Key.UP:
				if( highlightIndex != null && highlightIndex > 0 ) {
					highlightIndex--;
					refreshHighlight();
				}
				return false;
			case hxd.Key.DOWN:
				if( highlightIndex != null && highlightIndex < visible.length - 1 ) {
					highlightIndex++;
					refreshHighlight();
				}
				return false;
			case hxd.Key.PGUP:
				resetHighlight();
				return false;
			case hxd.Key.PGDOWN:
				if( visible.length > 0 ) {
					highlightIndex = visible.length - 1;
					refreshHighlight();
				}
				return false;
			case hxd.Key.ENTER:
				if (highlightIndex != null) {
					applyValue(visible[highlightIndex].id);
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
