package hide.view;

class Domkit extends FileView {

	var cssEditor : hide.comp.DomkitEditor;
	var dmlEditor : hide.comp.DomkitEditor;
	var paramsEditor : hide.comp.ScriptEditor;
	var prevSave : { css : String, dml : String, params : String };
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
				<tr class="title>
					<td>
						Parameters
					</td>
					<td class="separator">
					&nbsp;
					</td>
					<td>
						&nbsp;
					</td>
				</tr>
				<tr>
					<td class="paramsEditor">
					</td>
					<td class="separator">
					&nbsp;
					</td>
					<td>
						&nbsp;
					</td>
				</tr>
			</table>
			<div class="scene"></div>
		</div>');

		var content = sys.io.File.getContent(getPath());
		var data = hrt.impl.DomkitViewer.parse(content);
		prevSave = data;
		dmlEditor = new hide.comp.DomkitEditor(config, DML, data.dml, element.find(".dmlEditor"));
		cssEditor = new hide.comp.DomkitEditor(config, Less, data.css, dmlEditor.checker, element.find(".cssEditor"));
		var checker = new hide.comp.DomkitEditor.DomkitChecker(config);
		paramsEditor = new hide.comp.ScriptEditor(data.params, checker, element.find(".paramsEditor"));
		cssEditor.onChanged = dmlEditor.onChanged = paramsEditor.onChanged = check;
		cssEditor.onSave = dmlEditor.onSave = paramsEditor.onSave = save;

		// add a scene so the CssParser can resolve Tiles
		var scene = element.find(".scene");
		new hide.comp.Scene(config, scene, scene).onReady = function() check();
	}

	function check() {
		modified = prevSave.css != cssEditor.code || prevSave.dml != dmlEditor.code || prevSave.params != paramsEditor.code;
		var allParams = new Map();
		dmlEditor.checker.params = allParams;
		var comp = dmlEditor.getComponent();
		paramsEditor.doCheckScript();
		var checker = cast(paramsEditor.checker,hide.comp.DomkitEditor.DomkitChecker);
		var tparams = try @:privateAccess checker.typeCode(paramsEditor.code,0) catch( e : hscript.Expr.Error ) null;
		if( tparams == null ) tparams = TAnon([]);
		switch( tparams ) {
		case TAnon(fields):
			var any : hscript.Checker.TType = TUnresolved("???");
			for( f in fields ) {
				var t = f.t;
				function setRec(t:hscript.Checker.TType) {
					switch( t ) {
					case TMono(r) if( r.r == null ): r.r = any;
					default:
					}
					switch( t ) {
					case TMono(r) if( r.r != null ): setRec(r.r);
					case TNull(t): setRec(t);
					case TInst(_,tl), TAbstract(_,tl), TEnum(_,tl), TType(_,tl):
						for( t in tl ) setRec(t);
					case TFun(args,ret):
						for( t in args ) setRec(t.t);
						setRec(ret);
					case TAnon(fl):
						for( f in fl )
							setRec(f.t);
					case TLazy(f):
						setRec(f());
					default:
					}
				}
				setRec(t);
				allParams.set(f.name, t);
			}
		case null, _:
			paramsEditor.setError("Params definition is missing", 0, 0, 0);
		}
		dmlEditor.check();
		cssEditor.check();
	}

	function trimSpaces( code : String ) {
		code = StringTools.trim(code);
		code = [for( l in code.split("\n") ) StringTools.rtrim(l)].join("\n");
		return code;
	}

	override function save() {
		super.save();
		var data = {
			css : trimSpaces(cssEditor.code),
			dml : trimSpaces(dmlEditor.code),
			params : trimSpaces(paramsEditor.code),
		};
		var str = hrt.impl.DomkitViewer.toStr(data);
		prevSave = data;
		if( data.css != cssEditor.code ) cssEditor.setCode(data.css);
		if( data.dml != dmlEditor.code ) dmlEditor.setCode(data.dml);
		if( data.params != paramsEditor.code ) paramsEditor.setCode(data.params);
		sys.io.File.saveContent(getPath(),str);
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