package hide.html.comp;

import hide.html.WebComponent;
import js.Browser.document;
import js.Browser.window;
import js.html.*;

/**
	Lays out its children in a row (or column with `direction="vertical"`), separated by draggable splitters.
	A child with `anchor="previous"` or `anchor="next"` keeps a fixed pixel size (from its `size` attribute, reset when it changes),
	measured from the splitter on that side. Other children stretch to share the remaining space.
	A child's `--min-panel-size` CSS property (registered, not inherited) sets its minimum size (read on rebuild and drag start).
	An anchored child's `--split-override-size` CSS property (same rules) replaces its pixel size while set.
	When space runs out, stretching children keep their minimum first.
	Dispatches `split-resize` with the pane sizes (px for anchored panes, fr otherwise) as detail when a drag ends.
**/
@:keep
class SplitContainer extends WebComponent {
	static inline var MIN_SIZE = 20;
	static inline var DEFAULT_SIZE = 200;

	var root : ShadowRoot;
	var layout : StyleElement;
	var panes : Array<Element> = [];
	var sizes = new js.lib.WeakMap<Float>();
	var mins = new js.lib.WeakMap<Float>();
	var overrides = new js.lib.WeakMap<Float>();
	var observer : MutationObserver;

	public function new() {
		super();
		root = attachShadow(cast {mode: "open", slotAssignment: "manual"});
		root.adoptedStyleSheets = [styleSheet];
		observer = new MutationObserver((records : Array<MutationRecord>, _) -> {
			for (r in records)
				if (r.attributeName == "size")
					sizes.delete(cast r.target);
			// style / class can only change the CSS properties of a pane: no rebuild needed
			if (Lambda.exists(records, r -> r.attributeName != "style" && r.attributeName != "class"))
				build();
			else {
				readStyles();
				applyLayout();
			}
		});
	}

	override public function connectedCallback() {
		build();
	}

	function isVertical() {
		return getAttribute("direction") == "vertical";
	}

	function isAnchored(pane : Element) {
		return pane.hasAttribute("anchor");
	}

	function build() {
		// Only direct children matter: a subtree observer would get the records of every view below
		observer.disconnect();
		observer.observe(this, {childList: true, attributes: true, attributeFilter: ["direction"]});
		for (i in 0...children.length)
			observer.observe(children[i], {attributes: true, attributeFilter: ["anchor", "hidden", "size", "style", "class"]});
		panes = [for (i in 0...children.length) if (!children[i].hidden) children[i]];
		for (p in panes)
			if (!sizes.has(p))
				sizes.set(p, defaultSize(p));

		layout = document.createStyleElement();
		root.innerHTML = "";
		root.append(layout);
		for (i => pane in panes) {
			if (i > 0)
				root.append(splitter(i - 1));
			var slot = document.createSlotElement();
			root.append(slot);
			slot.assign(pane);
		}
		readStyles();
		applyLayout();
	}

	function defaultSize(p : Element) {
		var size = Std.parseFloat(p.getAttribute("size"));
		return !isAnchored(p) ? 1 : Math.isNaN(size) ? DEFAULT_SIZE : size;
	}

	function readStyles() {
		for (p in panes) {
			var style = window.getComputedStyle(p);
			mins.set(p, Std.parseFloat(style.getPropertyValue("--min-panel-size")));

			// NaN when unset ("none")
			var size = Std.parseFloat(style.getPropertyValue("--split-override-size"));
			var cleared = overrides.has(p) && !Math.isNaN(overrides.get(p)) && Math.isNaN(size);
			if (cleared)
				sizes.set(p, defaultSize(p));
			overrides.set(p, size);
		}
	}

	function applyLayout() {
		var stretchMin = 0.;
		var anchoredMin = 0.;
		for (p in panes)
			if (isAnchored(p))
				anchoredMin += mins.get(p);
			else
				stretchMin += mins.get(p);
		// Space left to anchored panes once stretching panes have their minimum
		var free = '(100% - ${stretchMin}px - ${panes.length - 1} * var(--splitter-size, 4px))';
		var tracks = [for (p in panes) {
			var min = mins.get(p);
			if (!isAnchored(p))
				'minmax(${min}px, ${sizes.get(p)}fr)';
			else {
				// Anchored minimums shrink proportionally when they don't fit in the free space
				var softMin = min > 0 ? 'min(${min}px, max(0px, $free * ${min / anchoredMin}))' : "0px";
				var size = overrides.get(p);
				'minmax($softMin, ${Math.isNaN(size) ? sizes.get(p) : size}px)';
			}
		}].join(" var(--splitter-size, 4px) ");
		var main = isVertical() ? "rows" : "columns";
		var cross = isVertical() ? "columns" : "rows";
		layout.textContent = ':host { grid-template-$main: $tracks; grid-template-$cross: minmax(0, 1fr); }';
	}

	function splitter(i : Int) {
		var el = document.createDivElement();
		el.className = "splitter";
		el.setAttribute("part", "splitter");
		el.onpointerdown = (e : PointerEvent) -> {
			e.preventDefault();
			el.setPointerCapture(e.pointerId);
			readStyles();
			var vertical = isVertical();
			function pos(e : PointerEvent) return vertical ? e.clientY : e.clientX;
			function length(p : Element) {
				var r = p.getBoundingClientRect();
				return vertical ? r.height : r.width;
			}
			var before = panes[i];
			var after = panes[i + 1];
			var start = pos(e);
			var first = length(before);
			var second = length(after);
			var fr = sizes.get(before) + sizes.get(after);
			el.onpointermove = (e : PointerEvent) -> {
				var delta = Math.max(mins.get(before) - first, Math.min(second - mins.get(after), pos(e) - start));
				// An anchored pane only resizes when the splitter on its free side moves
				if (before.getAttribute("anchor") == "previous")
					sizes.set(before, first + delta);
				if (after.getAttribute("anchor") == "next")
					sizes.set(after, second - delta);
				if (!isAnchored(before) && !isAnchored(after)) {
					sizes.set(before, fr * (first + delta) / (first + second));
					sizes.set(after, fr - sizes.get(before));
				}
				applyLayout();
			};
			el.onlostpointercapture = () -> {
				el.onpointermove = null;
				el.onlostpointercapture = null;
				dispatchEvent(new CustomEvent("split-resize", {detail: [for (p in panes) sizes.get(p)]}));
			};
		};
		return el;
	}

	static var _ = {
		CSS.registerProperty({name: "--min-panel-size", syntax: "<length>", inherits: false, initialValue: '${MIN_SIZE}px'});
		CSS.registerProperty({name: "--split-override-size", syntax: "<length> | none", inherits: false, initialValue: "none"});
		register(SplitContainer, "hide-split-container");
	}
}
