package hide.view;

class Domkit extends FileView {

	var cssEditor : hide.comp.DomkitEditor;
	var dmlEditor : hide.comp.DomkitEditor;
	var prevSave : { css : String, dml : String };
	var checker : hide.comp.DomkitEditor.DomkitChecker;

	override function onDisplay() {

		element.html('
		<div class="domkitEditor">
			<table>
				<tr class="title">
					<td>
						DML
					</td>
					<td class="separator">
					&nbsp;
					</td>
					<td>
						CSS
					</td>
				</tr>
				<tr>
					<td class="dmlEditor">
					</td>
					<td class="separator">
					&nbsp;
					</td>
					<td class="cssEditor">
					</td>
				</tr>
			</table>
			<div class="scene"></div>
		</div>');

		var content = sys.io.File.getContent(getPath());
		var cssText = "";

		if( StringTools.startsWith(content,"<css>") ) {
			var pos = content.indexOf("</css>");
			cssText = content.substr(5, pos - 5);
			content = content.substr(pos + 6);
		}

		var dmlText = StringTools.trim(content);
		cssText = StringTools.trim(cssText);

		prevSave = { css : cssText, dml : dmlText };
		dmlEditor = new hide.comp.DomkitEditor(config, DML, dmlText, element.find(".dmlEditor"));
		cssEditor = new hide.comp.DomkitEditor(config, Less, cssText, dmlEditor.checker, element.find(".cssEditor"));
		cssEditor.onChanged = dmlEditor.onChanged = check;
		cssEditor.onSave = dmlEditor.onSave = save;

		// add a scene so the CssParser can resolve Tiles
		var scene = element.find(".scene");
		new hide.comp.Scene(config, scene, scene).onReady = function() check();
	}

	function check() {
		modified = prevSave.css != cssEditor.code || prevSave.dml != dmlEditor.code;
		dmlEditor.check();
		cssEditor.check();
	}

	override function save() {
		super.save();
		var cssText = cssEditor.code;
		var dmlText = dmlEditor.code;
		sys.io.File.saveContent(getPath(),'<css>\n$cssText\n</css>\n$dmlText');
		prevSave = { css : cssText, dml : dmlText };
	}

	override function getDefaultContent() {
		var tag = getPath().split("/").pop().split(".").shift();
		return haxe.io.Bytes.ofString('<css>\n$tag {\n}\n</css>\n<$tag>\n</$tag>');
	}

	static var _ = FileTree.registerExtension(Domkit,["domkit"],{ icon : "id-card-o", createNew : "Domkit Component" });

}

class DomkitLess extends FileView {

	var editor : hide.comp.DomkitEditor;

	override function onDisplay() {
		super.onDisplay();
		var content = sys.io.File.getContent(getPath());
		element.html('<div class="lesseditor">
			<div class="scene"></div>
		</div>');
		editor = new hide.comp.DomkitEditor(config, Less, content, element.find(".lesseditor"));
		editor.onSave = function() {
			content = editor.code;
			save();
		};
		editor.onChanged = function() {
			modified = content != editor.code;
			editor.check();
		};
		// add a scene so the CssParser can resolve Tiles
		var scene = element.find(".scene");
		new hide.comp.Scene(config, scene, scene).onReady = function() editor.check();
	}

	override function save() {
		super.save();
		sys.io.File.saveContent(getPath(), editor.code);
		// TODO : execute lessc
	}

	static var _ = FileTree.registerExtension(DomkitLess,["less"],{ icon : "object-group" });

}