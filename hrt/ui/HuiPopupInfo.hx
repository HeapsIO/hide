package hrt.ui;

#if hui

class HuiPopupInfo extends HuiPopup {
	static var SRC =
	<hui-popup-info>
		<hui-text id="text-info"/>
	</hui-popup-info>

	static var inst : HuiPopupInfo = null;
	var time : Float = 0;

	public function new(time : Float, ?parent: h2d.Object) {
		super(parent);
		initComponent();

		this.time = time;

		if (inst != null)
			inst.remove();

		inst = this;
	}

	public function setText(text : String) {
		this.textInfo.text = text;
	}

	override function onRemove() {
		super.onRemove();
		if (inst == this)
			inst = null;
	}

	override function sync(ctx) {
		super.sync(ctx);

		time -= ctx.elapsedTime;
		if (time < 0)
			this.remove();
	}
}

#end