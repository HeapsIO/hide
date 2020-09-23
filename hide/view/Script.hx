package hide.view;

class Script extends FileView {

	var editor : monaco.ScriptEditor;
	var script : hide.comp.ScriptEditor;
	var originData : String;

	override function onDisplay() {
		element.addClass("script-editor");
		var lang = switch( extension ) {
		case "js", "hx": "javascript";
		case "json": "json";
		case "xml": "xml";
		case "html": "html";
		default: "text";
		}
		originData = sys.io.File.getContent(getPath());
		if( extension == "hx" ) {
			script = new hide.comp.ScriptEditor(originData, new hide.comp.ScriptEditor.ScriptChecker(config,"hx"), element);
			script.onSave = function() onSave(script.code);
			script.onChanged = function() {
				modified = script.code != originData;
				script.doCheckScript();
			}
		} else {
			editor = monaco.ScriptEditor.create(element[0],{
				value : originData,
				language : lang,
				automaticLayout : true,
				wordWrap : true,
				theme : "vs-dark",
			});
			editor.addCommand(monaco.KeyCode.KEY_S | monaco.KeyMod.CtrlCmd, function() {
				onSave(editor.getValue({preserveBOM:true}));
			});
			editor.onDidChangeModelContent(function() {
				var cur = editor.getValue({preserveBOM:true});
				modified = cur != originData;
			});
		}
	}

	function onSave(data) {
		originData = data;
		modified = false;
		skipNextChange = true;
		sys.io.File.saveContent(getPath(), originData);
	}

	static var _ = {
		FileTree.registerExtension(Script,["js","hx"],{ icon : "file-code-o" });
		FileTree.registerExtension(Script,["xml","html"],{ icon : "code" });
		FileTree.registerExtension(Script,["json"],{ icon : "gears" });
	};

}