package hrt.ui;


#if hui

enum ToastKind {
	Info;
	Warning;
	Error;
}

class HuiToast extends HuiElement {
	static var SRC =
		<hui-toast>
			<hui-element id="icon-container">
				<hui-element id="icon"/>
			</hui-element>
			<hui-element id="text-container">
				<hui-text("") id="text"/>
			</hui-element>
		</hui-toast>

	var timer : Float;
	var startTimer : Float;
	var kind: ToastKind;

	public function new(message: String, kind: ToastKind, ?timeoutSec: Float, ?parent) {
		super(parent);
		initComponent();

		timeoutSec ??= 5.0;

		timer = timeoutSec;
		startTimer = timeoutSec;
		text.text = message;
		this.kind = kind;

		switch (kind) {
			case Info:
				dom.addClass("info");
			case Warning:
				dom.addClass("warning");
			case Error:
				dom.addClass("error");
		}

		onClick = (e) -> {
			remove();
		}
	}

	public function canMerge(message: String, kind: ToastKind) {
		return startTimer - timer < 0.5 && text.text == message && this.kind == kind;
	}

	public function resetTimer() {
		timer = startTimer;
	}

	override function sync(ctx:h2d.RenderContext) {
		super.sync(ctx);
		if (!dom.hover)
			timer -= ctx.elapsedTime;
		if (timer < 0) {
			remove();
		}

		if (textContainer.huiBg != null) {
			textContainer.huiBg.background = 0xFFFFFF;
			// makes the toast flash when spawned
			textContainer.huiBg.backgroundAlpha = hxd.Math.pow(1.0 - hxd.Math.clamp(startTimer - timer),3.0) * 0.4;
		}
	}
}

#end