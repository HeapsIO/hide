package hide.comp;

class SubWindow {
	public var window(default, null) : js.html.Window;
	public var anchor : js.html.Element;
	public var title(get, set) : String;
	function get_title() return doc.title;
	function set_title(v: String) return doc.title = v;

	var doc : js.html.HTMLDocument;
	var root : js.html.Element;
	var timer : haxe.Timer;
	var sizeOffset = { w: 0., h: 0. };

	public function new(width: Int, height: Int, key: String) {
		var main = js.Browser.window;
		var bounds : { x: Float, y: Float, w: Float, h: Float } = hide.Ide.inst.globalState.get(key);
		bounds ??= { x: main.screenX + (main.outerWidth - width) / 2, y: main.screenY + (main.outerHeight - height) / 2, w: width, h: height };

		window = electron.Window.openSub(bounds.x, bounds.y, bounds.w, bounds.h);
		doc = cast window.document;
		window.requestAnimationFrame((_) -> sizeOffset = { w: bounds.w - window.innerWidth, h: bounds.h - window.innerHeight });
		for (s in js.Browser.document.querySelectorAll('link[rel="stylesheet"]')) {
			var link : js.html.LinkElement = cast doc.createElement("link");
			link.rel = "stylesheet";
			link.href = (cast s : js.html.LinkElement).href;
			doc.head.appendChild(link);
		}
		doc.body.classList.add("kit-sub-window");
		root = doc.createElement("kit-root");
		doc.body.appendChild(root);

		window.addEventListener("resize", (_) -> onResize());
		window.addEventListener("keydown", (e) -> onKeyDown(e));
		window.addEventListener("beforeunload", (_) -> {
			hide.Ide.inst.globalState.set(key, { x: window.screenX, y: window.screenY, w: window.innerWidth + sizeOffset.w, h: window.innerHeight + sizeOffset.h });
			main.removeEventListener("beforeunload", close);
			timer.stop();
			onClose();
		});
		main.addEventListener("beforeunload", close);

		// Manage closing of the window if anchor disappear
		timer = new haxe.Timer(300);
		timer.run = () -> if (anchor != null && !js.Browser.document.body.contains(anchor)) close();
	}

	public function setContent(content: js.html.Element) {
		root.replaceChildren(content);
	}

	public function close() {
		window.close();
	}

	public function focus() {
		window.focus();
	}

	public dynamic function onKeyDown(e: js.html.KeyboardEvent) {}
	public dynamic function onResize() {}
	public dynamic function onClose() {}
}
