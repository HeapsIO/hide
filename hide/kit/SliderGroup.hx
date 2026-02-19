package hide.kit;

#if domkit

class SliderGroup extends Line {
	public var isLocked : Bool = true;

	var labelGroup : NativeElement;
	var lock : NativeElement;
	var lockIcon : NativeElement;

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

		lock = huiLock;

		#end


		isLocked = getSetting(Global, "lock") ?? true;
		refresh();

		stealChildLabel(labelGroup);

		setupPropLine(labelGroup, null);

		if (multiline) {
			native.addClass("multiline");
		}
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