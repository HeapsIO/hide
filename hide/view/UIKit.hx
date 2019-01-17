package hide.view;

typedef UIKitDefinition = {
	var type : String;
	var html : String;
	var json : {};
}

class UIKit extends FileView {

	var scene : hide.comp.Scene;
	var uiElt : UIKitDefinition;
	var editor : hide.comp.CodeEditor;
	var lastSaveHtml : String;
	var doc : h2d.uikit.Document;
	var cssFiles : Array<String>;
	var sheets : h2d.uikit.CssStyle;
	var root : h2d.Flow;

	override function getDefaultContent() {
		var p : UIKitDefinition = {
			type : "ui",
			html : "",
			json : {},
		};
		return haxe.io.Bytes.ofString(ide.toJSON(p));
	}

	override function onDisplay() {
		super.onDisplay();
		uiElt = ide.parseJSON(sys.io.File.getContent(ide.getPath(state.path)));
		lastSaveHtml = uiElt.html;

		this.element.html('
			<div class="uikit">
				<div class="leftpanel">
					<div class="html"></div>
					<div class="cssErrors"></div>
				</div>
				<div class="scene">
				</div>
			</div>
		');
		scene = new hide.comp.Scene(config,null,element.find(".scene"));
		scene.onResize = onSceneResize;
		scene.onReady = sync;
		editor = new hide.comp.CodeEditor(uiElt.html, "xml", element.find(".html"));
		editor.onChanged = function() {
			var cur = editor.code;
			modified = cur != lastSaveHtml;
			uiElt.html = cur;
			sync();
		};
		editor.onSave = save;

		cssFiles = this.config.get("uikit.css");
		for( f in cssFiles )
			watch(f, function() {
				loadSheets();
				if( doc != null ) doc.setStyle(sheets);
				scene.refreshIfUnfocused = true;
			});
	}

	function loadSheets() {
		sheets = new h2d.uikit.CssStyle();
		var warnings = [];
		for( f in cssFiles ) {
			var content = sys.io.File.getContent(ide.getPath(f));
			var parser = new h2d.uikit.CssParser();
			var css = parser.parseSheet(content);
			sheets.add(css);
			for( w in parser.warnings )
				warnings.push({ file : f, line : content.substr(0,w.end).split("\n").length+1, msg : w.msg });
		}
		var warns = element.find(".cssErrors");
		warns.html([for( w in warnings ) w.file+":"+w.line+": "+StringTools.htmlEscape(w.msg)].join("<br>"));
		warns.toggle(warnings.length > 0);
	}

	function sync() {
		if( sheets == null )
			loadSheets();
		editor.clearError();
		var xml = try haxe.xml.Parser.parse(uiElt.html) catch( e : haxe.xml.Parser.XmlParserException ) {
			editor.setError(e.message, e.lineNumber, e.position, e.position+1);
			return;
		};
		if( doc != null ) {
			doc.remove();
			doc = null;
		}

		var b = new h2d.uikit.Builder();
		doc = b.build(xml);
		if( b.errors.length > 0 )
			editor.setError(b.errors.join("\n"), 1, 0, uiElt.html.length);

		if( root == null ) {
			root = new h2d.Flow(scene.s2d);
			onSceneResize();
			root.horizontalAlign = Middle;
			root.verticalAlign = Middle;
		}
		doc.addTo(root);
		doc.setStyle(sheets);
	}

	function onSceneResize() {
		if( root == null ) return;
		root.minWidth = root.maxWidth = scene.s2d.width;
		root.minHeight = root.maxHeight = scene.s2d.height;
	}

	override function save() {
		sys.io.File.saveContent(ide.getPath(state.path), ide.toJSON(uiElt));
		super.save();
	}

	static var _ = FileTree.registerExtension(UIKit, ["ui"], { icon : "id-card-o", createNew : "UI Component" });
}
