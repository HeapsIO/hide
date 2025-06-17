package hide.comp;

typedef RadialMenuItem = {
    ?label: String,
    ?click: Void -> Void,
    ?enabled: Bool,
    ?icon: String,
    ?tooltip: String,
}


class RadialMenu {
	static var inst : RadialMenu;

    var rootElement : js.html.Element;
	var centerElement : Element;
	var selectionElement : Element;
	var radialButtons : Array<Element> = [];
	var radialItems : Array<RadialMenuItem> = [];

	public function new(items: Array<RadialMenuItem>, absPos: {x: Float, y: Float} = null) {
		radialItems= items;

		var parent = js.Browser.document.body;
		rootElement = js.Browser.document.createDivElement();
        rootElement.setAttribute("tabindex", "-1");
        parent.appendChild(rootElement);

		rootElement.classList.add("radial-menu");

		var width = Std.parseInt(js.Browser.window.getComputedStyle(rootElement).width);
		var height = Std.parseInt(js.Browser.window.getComputedStyle(rootElement).height);
		rootElement.style.left = '${absPos.x - width / 2}px';
        rootElement.style.top = '${absPos.y - height / 2}px';

		centerElement = new Element('<div class="center ico ico-circle-o"></div>');
		centerElement.appendTo(rootElement);
		centerElement.get(0).style.left = '${(width / 2) - centerElement.width() / 2}px';
		centerElement.get(0).style.top = '${(height / 2) - centerElement.height() / 2}px';

		selectionElement = new Element('<div class="center-selection ico ico-circle-o"></div>');
		selectionElement.appendTo(centerElement);
		selectionElement.get(0).style.left = '${0}px';
		selectionElement.hide();


		// Create buttons
		for (idx => i in items) {
			var item = new Element('<div class="radial-button">
				<div class="ico ico-${i.icon}"></div>
				<span>${i.label}</span>
			</div>');
			item.appendTo(rootElement);

			function getPointsOnCircle(radius: Float, number : Int) {
				var pts = [];
				for (idx in 0...number) {
					var t = idx / number;
					var a = t * 2 * Math.PI;
					var x = Math.sin(a) * radius;
					var y = Math.cos(a) * radius;
					var p = new h2d.col.Point(x, y);
					pts.push(p);
				}

				return pts;
			}

			var xCenter = (width / 2) - (item.width() / 2);
			var yCenter = (height / 2) - (item.height() / 2);
			item.get(0).style.left = '${xCenter}px';
			item.get(0).style.top = '${yCenter}px';
			item.width(); // Force recompute of style
			var x = getPointsOnCircle(150, items.length)[idx].x;
			var y = getPointsOnCircle(150, items.length)[idx].y;
			item.get(0).style.left = '${xCenter + x}px';
        	item.get(0).style.top = '${yCenter + y}px';
			radialButtons.push(item);
		}

		var el = new Element(rootElement.ownerDocument.body);
		el.on("mousemove.radialMenu", update);
		el.on("keyup.radialMenu", function(e: js.jquery.Event) {
			el.off("mousemove.radialMenu");
			el.off("keyup.radialMenu");
			stop();
		});
	}

	public static function createFromPoint(x: Float, y: Float, items: Array<RadialMenuItem>) {
		if (inst != null)
			return;
        inst = new RadialMenu(items, {x:x, y:y});
    }

	function update(e: js.jquery.Event) {
		var mousePos = new h2d.col.Point(e.clientX, e.clientY);
		var center = new h2d.col.Point(centerElement.offset().left, centerElement.offset().top);
		center.x += centerElement.width() / 2;
		center.y += centerElement.height() / 2;

		var dir = mousePos - center;
		var magnitude = dir.length();
		dir.normalize();

		selectionElement.hide();
		new Element(rootElement).find(".selected").removeClass("selected");
		if (magnitude < 30)
			return;

		selectionElement.show();
		var dot = (dir.x * 0) + (dir.y * 1);
		var angle = dir.x > 0 ? 2 * hxd.Math.PI - hxd.Math.acos(dot) : hxd.Math.acos(dot);
		var anglePerEl = (2 * hxd.Math.PI) / radialButtons.length;
		var idxSelected = (radialButtons.length - 1) - Std.int((angle - (anglePerEl / 2)) / anglePerEl);
		selectionElement.css({ "transform" : 'rotate(${angle}rad)'});

		radialButtons[idxSelected].addClass("selected");
	}

	function stop() {
		for (idx => i in radialButtons) {
			if (i.hasClass("selected"))
				if (radialItems[idx].click != null)
					radialItems[idx].click();
		}

		rootElement.remove();
		inst = null;
	}
}