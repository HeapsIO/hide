package hrt.ui;

#if hui

class HuiFmtTextInput extends h2d.TextInput implements h2d.domkit.Object {
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
	}

	public var preventDefault = false;
}

#end