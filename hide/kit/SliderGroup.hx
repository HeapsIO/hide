package hide.kit;

#if domkit

class SliderGroup extends Line {
	public var isLocked : Bool = true;

	var labelGroup : NativeElement;
	var lock : NativeElement;
	var lockIcon : NativeElement;

	#if hui
	var lineContent : NativeElement;
	override function get_nativeContent():NativeElement {
		return lineContent;
	}
	#end

	override function makeSelf():Void {


		labelGroup = NativeElement.create("kit-label");


		#if js

		lock = new hide.Element('<fancy-button class="fancy-tiny quiet" title="Link sliders">')[0];
		lockIcon = new hide.Element('<div class="icon ico">')[0];
		lock.addChild(lockIcon);

		lock.get().onclick = (e: js.html.MouseEvent) -> {
			isLocked = !isLocked;
			saveSetting(Global, "lock", isLocked ? null : false);
			refresh();
		}

		labelGroup.addChild(lock);


		if (label != null) {
			labelElement = js.Browser.document.createSpanElement();
			labelElement.get().innerText = label ?? "";
			labelGroup.addChild(labelElement);
		}

		#elseif hui

		var huiLock = new hrt.ui.HuiElement(labelGroup);
		huiLock.dom.addClass("kit-lock");

		huiLock.onClick = (e) ->  {
			isLocked = !isLocked;
			saveSetting(Global, "lock", isLocked ? null : false);
			refresh();
		}

		if (label != null) {
			labelElement = NativeElement.create("kit-label");
			new hrt.ui.HuiText(label, labelElement);
			labelGroup.addChild(labelElement);
		}

		lock = huiLock;

		#end


		isLocked = getSetting(Global, "lock") ?? true;
		refresh();

		stealChildLabel(labelGroup);

		#if js

		setupPropLine(labelGroup, null);

		if (multiline) {
			native.addClass("multiline");
		}

		#else

		lineContent = new hrt.ui.HuiLine();
		setupPropLine(labelGroup, lineContent);

		#end
	}

	function refresh() {
		#if js
        lockIcon.toggleClass("ico-link", isLocked);
        lockIcon.toggleClass("ico-unlink", !isLocked);
		#elseif hui
        lock.toggleClass("locked", isLocked);
		#end
	}
}

#end