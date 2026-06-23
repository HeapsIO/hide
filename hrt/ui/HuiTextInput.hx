package hrt.ui;

#if hui

class HuiTextInput extends h2d.TextInput implements h2d.domkit.Object {
	@:p public var baseFont(never, set) : String;

	public function new(?txt : String, ?maxCharacters: Int, ?parent) {
		super(hxd.res.DefaultFont.get(), parent);
		initComponent();

		interactive.onKeyDown = function(e:hxd.Event) {
			preventDefault = false;
			if(HuiBase.get(this).checkCommand(e, this))
				return;
			onKeyDown(e);
			if (preventDefault) {
				return;
			}
			handleKey(e);
		};
	}


	function set_baseFont(v : String) {
		font = HuiText.loadFontStatic(v);
		return v;
	}

	public var preventDefault = false;
}

#end