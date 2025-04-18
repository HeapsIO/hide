package hide.comp;

class CodeEditor extends Component {

	static var INIT_DONE = false;
	static var COMPLETIONS = [];

	var lang : String;
	var editor : monaco.ScriptEditor;
	var errorMessage : Element;
	var currrentDecos : Array<String> = [];
	public var code(get,never) : String;
	public var propagateKeys : Bool = false;
	public var saveOnBlur : Bool = true;

	public function new( code : String, lang : String, ?parent : Element, ?root : Element ) {

		if( !INIT_DONE ) {
			INIT_DONE = true;
			// disable default completion
			(monaco.Languages : Dynamic).typescript.javascriptDefaults.setModeConfiguration({ completionItems : false });
			(monaco.Languages : Dynamic).html.htmlDefaults.setModeConfiguration({ completionItems : false });
			(monaco.Languages : Dynamic).css.lessDefaults.setModeConfiguration({ completionItems : false });
		}

		super(parent,root);
		var root = element;
		this.lang = lang;
		root.addClass("codeeditor");
		root.on("keydown", function(e) {
			if( e.keyCode == 27 && root.find(".suggest-widget.visible").length == 0 ) onClose();
			if( !propagateKeys ) e.stopPropagation();
		});
		editor = monaco.ScriptEditor.create(root[0],{
			value : code,
			language : lang == null ? "javascript" : lang,
			automaticLayout : true,
			wordWrap : true,
			minimap : { enabled : false },
			theme : "vs-dark",
			lineNumbersMinChars: 3,
			fontSize: "13px",
			mouseWheelZoom: true,
			scrollBeyondLastLine: false,
			insertSpaces : false,
			detectIndentation : false,
			// To remove when scrollbar's bug is fixed (error when user click on scrollbar)
			scrollbar: {
				vertical:"hidden",
				horizontal: "hidden",
				handleMouseWheel:true,
			},
		});
		var model = editor.getModel();
		(model : Dynamic).__comp__ = this;
		errorMessage = new Element('<div class="codeErrorMessage"></div>').appendTo(root).hide();
		model.updateOptions({ insertSpaces:false, trimAutoWhitespace:true });
		editor.onDidChangeModelContent(function() onChanged());
		editor.onDidBlurEditorText(function() if( saveOnBlur ) onSave());

		// This is needed because from monaco editor v0.31.1 to current version, commands added are global and not per editor (this is a bug)
		editor.onDidFocusEditorText(function() {
			editor.addCommand(monaco.KeyCode.KEY_S | monaco.KeyMod.CtrlCmd, function() {
				saveBind();
			});
		});
	}

	function saveBind() {
		clearSpaces();
		onSave();
		customCtrlSBehavior();
	}

	public dynamic function customCtrlSBehavior() {
	}

	function initCompletion( ?chars ) {
		if( COMPLETIONS.indexOf(lang) < 0 ) {
			COMPLETIONS.push(lang);
			monaco.Languages.registerCompletionItemProvider(lang, {
				triggerCharacters : chars,
				provideCompletionItems : function(model,position,_,_) {
					var comp : CodeEditor = (model : Dynamic).__comp__;
			        var code = model.getValueInRange({startLineNumber: 1, startColumn: 1, endLineNumber: position.lineNumber, endColumn: position.column});
					var res = comp.getCompletion(code.length);
					for( r in res )
						if( r.insertText == null )
							r.insertText = r.label;

					return { suggestions : res };
				}
			});

			monaco.Languages.registerCompletionItemProvider(lang, {
				provideCompletionItems : function(model,position,_,_) {
					return { suggestions : getKeyWordsCompletion() };
				}
			});
		}
	}

	function getCompletion( position : Int ) : Array<monaco.Languages.CompletionItem> {
		return [];
	}

	function getKeyWordsCompletion() : Array<monaco.Languages.CompletionItem> {
		// Add keywords to autocompletion
		var keywords = ["if", "var", "while", "do", "for", "break", "function", "return", "new", "throw", "try", "switch", "case", "default"];

		var res = [];
		for (k in keywords) {
			res.push({
				label: k,
				kind: monaco.Languages.CompletionItemKind.Keyword,
				insertText: k,
			});
		}

		return res;
	}

	function clearSpaces() {
		var code = code;
		var newCode = [for( l in StringTools.trim(code).split("\n") ) StringTools.rtrim(l)].join("\n");
		if( newCode != code ) {
			var p = editor.getPosition();
			setCode(newCode, true);
			editor.setPosition(p);
		}
	}

	function get_code() {
		return editor.getValue({preserveBOM:true});
	}

	public function setCode( code : String, keepHistory : Bool = false ) {
		if ( keepHistory ) {
			editor.executeEdits('set_code', [{ identifier: 'delete', range: new monaco.Range(1, 1, 10000, 1), text: '', forceMoveMarkers: true }]);
			editor.executeEdits('set_code', [{ identifier: 'insert', range: new monaco.Range(1, 1, 1, 1), text: code, forceMoveMarkers: true }]);
			return;
		}

		editor.setValue(code);
	}

	public function focus() {
		editor.focus();
	}

	public dynamic function onChanged() {
	}

	public dynamic function onSave() {
	}

	public dynamic function onClose() {
	}

	public function clearError() {
		if( currrentDecos.length != 0 )
			currrentDecos = editor.deltaDecorations(currrentDecos,[]);
		errorMessage.toggle(false);
	}

	public function setError( msg : String, line : Int, pmin : Int, pmax : Int ) {
		var linePos = code.substr(0,pmin).lastIndexOf("\n");
		if( linePos < 0 ) linePos = 0 else linePos++;
		var delta = pmin == pmax ? 2 : 1;
		var range = new monaco.Range(line,pmin + 1 - linePos,line,pmax + delta - linePos);
		currrentDecos = editor.deltaDecorations(currrentDecos,[
			{ range : range, options : { inlineClassName: "codeErrorContentLine", isWholeLine : true } },
			{ range : range, options : { linesDecorationsClassName: "codeErrorLine", inlineClassName: "codeErrorContent" } }
		]);
		var errStr = '${[for( l in msg.split("\n") ) StringTools.htmlEscape(l)].join("<br/>")}';
		errorMessage.html(errStr);
		errorMessage.prop('title', errStr);
		errorMessage.toggle(true);
		var rect = errorMessage[0].getBoundingClientRect();
		if( rect.bottom > js.Browser.window.innerHeight )
			errorMessage[0].scrollIntoView(false);
	}

}