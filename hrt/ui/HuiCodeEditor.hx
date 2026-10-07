// Ported from https://github.com/ncannasse/picogpu/blob/main/src/CodeEditor.hx
package hrt.ui;

#if hui
import hxd.Key in K;

typedef HuiCodeCompletion = {
	var name : String;
	var ?info : String;
}

class HuiCodeTip extends HuiPopup {
	static var SRC = <hui-code-tip></hui-code-tip>;
	public var select(default,set) : Int = -1;
	public var tips : Array<h2d.Flow> = [];

	function set_select(v) {
		if( select >= 0 )
			tips[select].dom.removeClass("sel");
		this.select = v;
		if( select >= 0 )
			tips[select].dom.addClass("sel");
		return v;
	}

	override function sync(ctx:h2d.RenderContext) {
		super.sync(ctx);
		if( select >= 0 ) scrollIntoView(tips[select]);
	}

}

@:access(hrt.ui.HuiCodeEditor.HuiCodeTip)
@:access(hrt.ui.HuiCodeEditor.HuiCodeEditorInternal)
class HuiCodeEditor extends HuiElement {
	static var SRC =
		<hui-code-editor>
			<hui-text id="line-numbers"/>
			<hui-code-editor-internal id="editor"></hui-code-editor-internal>
		</hui-code-editor>

	public var currentTip : HuiCodeTip;

	public var value(get, set) : String;
	function get_value() {
		return editor.text;
	}

	function set_value(v) {
		editor.text = v;
		syncColors();
		syncLines();
		return editor.text;
	}


	public function new(?parent) {
		super(parent);
		initComponent();

		editor.onCodeChange = () -> {
			onCodeChange();
			syncLines();
			syncColors();
		}

		onAfterReflow = afterReflow;
	}

	function afterReflow() {
		editor.maxWidth = innerWidth-50;
	}

	public dynamic function onCodeChange() {

	}

	function syncLines() {
		var lines = [];
		for( i => line in editor.text.split("\n") ) {
			lines.push(""+(i+1));
			var subs = editor.splitText(line).split("\n");
			for( i in 1...subs.length ) lines.push("");
		}
		lineNumbers.text = lines.join("<br/>");
	}

	function syncColors() {
		var segs = new hscript.Colorizer().getColorSegments(editor.splitText(editor.text),0xEEEEEE);
		for( i in 0...segs.length>>1 )
			segs[i*2+1] |= 0xFF000000;
		editor.setColorSegments(segs);
	}

	// function getCompletion( position : Int ) : Array<CodeEditor.CodeCompletion> {
	// 	var parser = new hscript.Parser();
	// 	parser.allowTypes = true;
	// 	parser.resumeErrors = true;
	// 	var code = editor.text.substr(0, position);
	// 	var expr = parser.parseString(code, "");
	// 	var compl = try {
	// 		var et = checker.check(expr,null,true);
	// 		return null;
	// 	} catch( c : hscript.Checker.Completion ) {
	// 		c;
	// 	};
	// 	var fields = checker.getCompletion(compl);
	// 	return [for( f in fields ) { name : f.name, info : hscript.Checker.typeStr(f.t) }];
	// }
}

class HuiCodeEditorInternal extends h2d.TextInput implements h2d.domkit.Object {


	static var SRC = <hui-code-editor-internal></hui-code-editor-internal>;

	@:p public var baseFont(never, set) : String;

	function set_baseFont(v : String) {
		font = HuiText.loadFontStatic(v, false);
		return v;
	}

	var compFilter : String;
	var lastCompletion : Array<HuiCodeCompletion>;
	var autoInsert : String;

	var codeEditor(get, never) : HuiCodeEditor;
	function get_codeEditor() {return cast parent;};

	public var matchingInserts = ["{" => "}", "(" => ")", "[" => "]"];

	public function new(?parent) {
		super(hxd.res.DefaultFont.get(),parent);
		initComponent();
		if (!(parent is HuiCodeEditor))
			throw "parent must be a HuiCodeEditor";
		smooth = true;
		multiline = true;
		insertTabs = "    ";
	}

	function removeCompletion() {
		if( codeEditor.currentTip == null ) return;
		codeEditor.currentTip.remove();
		//style.removeObject(currentTip);
		codeEditor.currentTip = null;
		lastCompletion = null;
	}

	function updateCompletion( canReset=false ) {
		var compl = getCompletion(getTextPos(cursorIndex));
		if( compl == null ) {
			if( canReset || lastCompletion == null ) {
				removeCompletion();
				return;
			}
			compl = lastCompletion;
		}
		removeCompletion();
		var pos = getTextPos(cursorIndex);
		var prev = getTextPos(getWordStart());
		compFilter = text.substr(prev, pos - prev);
		if( StringTools.endsWith(compFilter,".") )
			compFilter = "";
		var tip = new HuiCodeTip();
		lastCompletion = [];
		for( c in compl ) {
			if( !StringTools.startsWith(c.name,compFilter) )
				continue;
			tip.tips.push(domkit.Component.build(
				<hui-text class="c name" text={c.name}/>
			, tip));
			lastCompletion.push(c);
		}
		//style.addObject(tip);
		if( tip.tips.length == 0 )
			removeCompletion();
		else {
			tip.select = 0;
			codeEditor.currentTip = tip;
			codeEditor.uiBase.addPopup(tip);
		}
	}

	override function onBlur() {
		super.onBlur();
		removeCompletion();
	}

	override function onCursorChange() {
		super.onCursorChange();
		removeCompletion();
	}

	override function draw(ctx) {
		super.draw(ctx);
		if( codeEditor.currentTip != null ) {
			codeEditor.currentTip.x = absX + cursorX - scrollX + cursorTile.dx;
			codeEditor.currentTip.y = absY + cursorY + cursorTile.dy + cursorTile.height;
		}
	}

	override function handleKey(e:hxd.Event) {
		var checkCompletion = false;
		var c = codeEditor.currentTip;
		if( c != null ) {
			switch( e.keyCode ) {
			case K.BACKSPACE, K.DELETE:
				checkCompletion = true;
			case K.UP:
				if( c.select > 0 ) c.select--;
				return;
			case K.DOWN:
				if( c.select < c.tips.length-1 ) c.select++;
				return;
			case K.PGDOWN, K.PGUP:
				var lines = Std.int(@:privateAccess c.calculatedHeight/c.tips[0].getBounds().height);
				if( e.keyCode == K.PGUP && c.select > 0 ) {
					var n = c.select - lines;
					if( n < 0 ) n = 0;
					c.select = n;
				}
				if( e.keyCode == K.PGDOWN && c.select < c.tips.length - 1 ) {
					var n = c.select + lines;
					if( n >= c.tips.length ) n = c.tips.length - 1;
					c.select = n;
				}
				return;
			case K.ESCAPE:
				removeCompletion();
				return;
			case K.TAB, K.ENTER:
				inputText("");
				return;
			default:
			}
		}
		super.handleKey(e);
		if( checkCompletion ) updateCompletion();
	}

	override function inputText(t:String) {
		if( autoInsert != null ) {
			/*
				If we type something that was auto-inserted, we will simply move the cursor
				Exemple : ( inserts a )
			*/
			if( StringTools.startsWith(autoInsert,t) ) {
				autoInsert = autoInsert.substr(t.length);
				if( autoInsert == "" ) autoInsert = null;
				cursorIndex += t.length;
				onChange();
				return;
			}
			autoInsert = null;
		}
		// auto trigger complete when inserting something
		if( codeEditor.currentTip != null && (t.length == 0 || (t.length == 1 && !~/[A-Za-z-0-9_]/.match(t))) ) {
			var comp = lastCompletion[codeEditor.currentTip.select].name;
			removeCompletion();
			beforeChange();
			selectionRange = { start : cursorIndex - compFilter.length, length : compFilter.length };
			inputText(comp);
		}
		var prevLine = t == "\n" ? getCurrentLine() : null;
		super.inputText(t);
		// auto insert matching parent/brace
		var extra = matchingInserts.get(t);
		if( extra != null ) {
			var prev = cursorIndex;
			super.inputText(extra);
			cursorIndex = prev;
			onChange();
			autoInsert = extra;
		}
		// keep previous line identation
		if( t == "\n" && prevLine != null ) {
			var ident = ~/^[ \t]+/;
			if( ident.match(prevLine.value) )
				super.inputText(ident.matched(0));
		}
	}

	public function setCode( code : String ) {
		text = code;
		removeCompletion();
	}

	override dynamic function onChange() {
		updateCompletion();
		onCodeChange();
	}

	public dynamic function onCodeChange() {
	}

	public dynamic function getCompletion( position : Int ) : Null<Array<HuiCodeCompletion>> {
		return null;
	}
}
#end