package hide.view;

class Script extends FileView {

	var editor : monaco.Editor;
	var originData : String;

	override function onDisplay() {

		if( monaco.Editor == null ) {
			element.html("<div class='hide-loading'></div>");
			haxe.Timer.delay(rebuild, 100);
			return;
		}
		var lang = switch( extension ) {
		case "js", "hx": "javascript";
		case "json": "json";
		case "xml": "xml";
		case "html": "html";
		default: "text";
		}
		originData = sys.io.File.getContent(getPath());
		editor = monaco.Editor.create(element[0],{
			value : originData,
			language : lang,
			automaticLayout : true,
			wordWrap : true,
			theme : "vs-dark",
		 });
		 editor.addCommand(monaco.KeyCode.KEY_S | monaco.KeyMod.CtrlCmd, function() {
			 originData = editor.getValue({preserveBOM:true});
			 modified = false;
			 sys.io.File.saveContent(getPath(), originData);
		 });
		 editor.onDidChangeModelContent(function() {
			 var cur = editor.getValue({preserveBOM:true});
			 modified = cur != originData;
		 });
	}

	static var _ = {
		FileTree.registerExtension(Script,["js","hx"],{ icon : "file-code-o" });
		FileTree.registerExtension(Script,["xml","html"],{ icon : "code" });
		FileTree.registerExtension(Script,["json"],{ icon : "gears" });
	};

}