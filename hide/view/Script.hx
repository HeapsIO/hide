package hide.view;

class Script extends FileView {

	var editor : monaco.ScriptEditor;
	var script : hide.comp.ScriptEditor;
	var originData : String;
	var lang : String;

	function getScriptChecker() {
		if( extension != "hx" )
			return null;
		return new hide.comp.ScriptEditor.ScriptChecker(config,"hx");
	}

	override function buildTabMenu():Array<hide.comp.ContextMenu.ContextMenuItem> {
		var arr = super.buildTabMenu();
		if( lang == "xml" ) {
			arr.push({ label : "Count Words", click : function() {
				var x = try Xml.parse(editor.getValue()) catch( e : Dynamic ) { ide.error(e); return; };
				var count = 0;
				function countRec(x:Xml) {
					switch( x.nodeType ) {
					case CData, PCData:
						count += StringTools.trim(~/[ \n\t\r]/g.replace(" ",x.nodeValue)).split(" ").length;
					case Element, Document:
						for( x in x )
							countRec(x);
					default:
					}
				}
				countRec(x);
				ide.message("Words : "+count);
			}});
		}
		return arr;
	}

	override function onDisplay() {
		element.addClass("script-editor");
		lang = switch( extension ) {
		case "js", "hx": "javascript";
		case "json": "json";
		case "xml": "xml";
		case "html": "html";
		default: "text";
		}
		originData = sys.io.File.getContent(getPath());
		var checker = getScriptChecker();
		if( checker != null ) {
			script = new hide.comp.ScriptEditor(originData, checker, element);
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