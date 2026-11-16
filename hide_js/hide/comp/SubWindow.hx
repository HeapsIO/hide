package hide.comp;

class SubWindow {
	public var window(default, null) : js.html.Window;
	public var anchor : js.html.Element;
	public var title(get, set) : String;
	function get_title() return doc.title;
	function set_title(v: String) {
		titleText.textContent = v;
		return doc.title = v;
	}

	var doc : js.html.HTMLDocument;
	var root : js.html.Element;
	var titleText : js.html.Element;
	var timer : haxe.Timer;
	var sizeOffset = { w: 0., h: 0. };

	static inline var TITLE_BAR_HEIGHT = 22; // .sub-window-title-bar height

	/**
		`width` and `height` are the content size, without the title bar.
		Without `key`, the window bounds are not saved.
	**/
	public function new(width: Int, height: Int, ?key: String, ?x: Float, ?y: Float) {
		var main = js.Browser.window;
		var bounds : { x: Float, y: Float, w: Float, h: Float } = key != null ? hide.Ide.inst.globalState.get(key) : null;
		height += TITLE_BAR_HEIGHT;
		bounds ??= { x: x ?? main.screenX + (main.outerWidth - width) / 2, y: y ?? main.screenY + (main.outerHeight - height) / 2, w: width, h: height };

		var screen = main.screen;
		bounds.x = Math.max(screen.availLeft, Math.min(bounds.x, screen.availLeft + screen.availWidth - bounds.w));
		bounds.y = Math.max(screen.availTop, Math.min(bounds.y, screen.availTop + screen.availHeight - bounds.h));

		window = electron.Window.openSub(bounds.x, bounds.y, bounds.w, bounds.h);
		doc = cast window.document;
		window.requestAnimationFrame((_) -> sizeOffset = { w: bounds.w - window.innerWidth, h: bounds.h - window.innerHeight });

		doc.open();
		doc.write("<!DOCTYPE html><html><head></head><body></body></html>");
		doc.close();

		for (s in js.Browser.document.querySelectorAll('link[rel="stylesheet"]')) {
			var link : js.html.LinkElement = cast doc.createElement("link");
			link.rel = "stylesheet";
			link.href = (cast s : js.html.LinkElement).href;
			doc.head.appendChild(link);
		}
		doc.body.classList.add("kit-sub-window");

		var titleBar = doc.createDivElement();
		titleBar.classList.add("sub-window-title-bar");
		titleText = doc.createSpanElement();
		titleBar.appendChild(titleText);
		var closeButton = doc.createButtonElement();
		closeButton.title = "Close";
		closeButton.innerHTML = '<i class="ico ico-close"></i>';
		closeButton.addEventListener("click", (_) -> close());
		titleBar.appendChild(closeButton);
		doc.body.appendChild(titleBar);

		root = doc.createElement("kit-root");
		doc.body.appendChild(root);

		window.addEventListener("resize", (_) -> onResize());
		window.addEventListener("keydown", (e) -> onKeyDown(e));
		window.addEventListener("beforeunload", (_) -> {
			if (key != null)
				hide.Ide.inst.globalState.set(key,{ x: window.screenX, y: window.screenY, w: window.innerWidth + sizeOffset.w, h: window.innerHeight + sizeOffset.h });
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
