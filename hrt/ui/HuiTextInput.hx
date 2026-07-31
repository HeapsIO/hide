package hrt.ui;

#if hui

class HuiTextInput extends h2d.TextInput implements h2d.domkit.Object {
	@:p public var baseFont(never, set) : String;

	public function new(?txt : String, ?maxCharacters: Int, ?parent) {
		super(hxd.res.DefaultFont.get(), parent);
		initComponent();

		interactive.onKeyDown = function(e:hxd.Event) {
			preventDefault = false;
			onKeyDown(e);
			if (preventDefault) {
				return;
			}
			handleKey(e);
		};

		smooth = true;
	}

	override public function focus( autoSelect=true ) {
		interactive.focus();
		if( cursorIndex < 0 ) {
			cursorIndex = getTextLength();
		}
		if( autoSelect && text != "" && !multiline ) setSelectionRange({ start : 0, length : getTextLength() });
	}

	public function setSelectionRange(range: {start: Int, length: Int}) {
		selectionRange = range;
		cursorIndex = range.length;
		onCursorChange();
	}


	function set_baseFont(v : String) {
		font = HuiText.loadFontStatic(v, false);
		return v;
	}

	public var preventDefault: Bool = false;
}

#end