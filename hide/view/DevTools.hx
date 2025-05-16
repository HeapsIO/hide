package hide.view;

class DevTools extends hide.ui.View<{ profileFilePath : String }> {
	var devtools : Element.HTMLElement;

	public function new( ?state ) {
		super(state);
	}

	override function onDisplay() {
		new Element('
		<div class="devtools">
			<webview id="webview-blank" src="blank.html" partition="persist:trusted"></webview>
			<webview id="webview-devtools" src="about:blank" partition="persist:trusted"></webview>
		</div>').appendTo(element);
		var blank = element.find("#webview-blank").get(0);
		devtools = element.find("#webview-devtools").get(0);
		var openCalled = false;
		var blankLoaded = false;
		var devtoolsLoaded = false;
		function tryOpen() {
			if( openCalled || !blankLoaded || !devtoolsLoaded )
				return;
			openCalled = true;
			showDevTools(blank, true, devtools);
			// wait for devTools ready
			haxe.Timer.delay(() -> openProfile(), 500);
		}
		blank.addEventListener("contentload", function() {
			blankLoaded = true;
			tryOpen();
		});
		devtools.addEventListener("contentload", function() {
			devtoolsLoaded = true;
			tryOpen();
		});
		if( this.state.profileFilePath != null )
			watch(this.state.profileFilePath, () -> openProfile());
	}

	override function buildTabMenu():Array<hide.comp.ContextMenu.MenuItem> {
		var menu = super.buildTabMenu();
		menu.push({isSeparator: true});
		menu.push({label: "Debug", click: () -> {
			showDevTools(devtools, true);
		}});
		return menu;
	}

	public function openProfile() {
		if( this.state.profileFilePath == null )
			return;
		try {
			var unsafeContent = sys.io.File.getContent(this.state.profileFilePath);
			// ensure that it's really a json
			var fileContent = haxe.Json.stringify(haxe.Json.parse(unsafeContent));
			unsafeExecuteScript('
var tmp = {};
tmp.fileContent = `${fileContent}`;
tmp.dataT = new DataTransfer();
tmp.dataT.items.add(new File([tmp.fileContent], "profile.json", {type: "application/json"}))
document.elementFromPoint(0, 0).shadowRoot.getElementById("tab-timeline").dispatchEvent(new MouseEvent("mousedown", {isTrusted: true, button: 0}));
setTimeout(function() {
	document.getElementsByClassName("timeline")[0].dispatchEvent(new DragEvent("dragover", {dataTransfer: tmp.dataT}));
	document.getElementsByClassName("timeline")[0].lastChild.dispatchEvent(new DragEvent("drop", {dataTransfer: tmp.dataT}));
}, 100);
			');
		} catch( e ) {
			ide.error("Unable to open profile: " + e.message);
			this.state.profileFilePath = null;
			saveState();
			syncTitle();
		}

	}

	inline function showDevTools( webview : Element.HTMLElement, show : Bool, ?container : Element.HTMLElement ) {
		js.Syntax.code("{0}.showDevTools({1}, {2});", webview, show, container);
	}

	inline function unsafeExecuteScript( script : String ) {
		js.Syntax.code("{0}.executeScript({ code: {1}, mainWorld: false });", devtools, script);
	}

	override function getTitle() {
		if( this.state.profileFilePath != null ) {
			var file = haxe.io.Path.withoutDirectory(this.state.profileFilePath);
			return "DevTools:" + file;
		}
		return "DevTools";
	}

	static var _ = hide.ui.View.register(DevTools);
}
