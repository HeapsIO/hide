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

			if (e.keyCode == hxd.Key.TAB) {
				var next : h2d.TextInput = null;
				var parent = this.parent;
				while (parent != null) {
					var inputs = parent.findAll((o) -> Std.downcast(o, h2d.TextInput));
					if (inputs != null && inputs.length > 1) {
						var curIdx = inputs.indexOf(this);
						if (curIdx != -1) {
							next = curIdx + 1 < inputs.length ? inputs[curIdx + 1] : inputs[0];
							break;
						}
					}
					parent = parent.parent;
				}

				if (next != null) {
					this.cursorIndex = -1;
					this.interactive.blur();
					next.focus();
				}

			}
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