package hide.kit;

#if domkit

class SliderGroup extends Line {
	public var isLocked : Bool = true;

	var labelGroup : NativeElement;
	var lock : NativeElement;
	var lockIcon : NativeElement;

	override function makeSelf():Void {
		#if js


		labelGroup = js.Browser.document.createElement("kit-label");

		lock = new hide.Element('<fancy-button class="fancy-tiny quiet" title="Link sliders">')[0];
		lockIcon = new hide.Element('<div class="icon ico">')[0];
		lock.appendChild(lockIcon);

		lock.onclick = (e: js.html.MouseEvent) -> {
			isLocked = !isLocked;
			saveSetting(Global, "lock", isLocked ? null : false);
			refresh();
		}
		isLocked = getSetting(Global, "lock") ?? true;
		refresh();

		labelGroup.appendChild(lock);


		if (label != null) {
			labelElement = js.Browser.document.createSpanElement();
			labelElement.innerText = label ?? "";
			labelGroup.appendChild(labelElement);
		}

		stealChildLabel(labelGroup);

		setupPropLine(labelGroup, null);

		if (multiline) {
			native.classList.add("multiline");
		}

		#elseif hui
		native = new hrt.ui.HuiElement();
		native.dom.addClass("line");
		//refreshLabel();
		#end
	}

	function refresh() {
		#if js
        lockIcon.classList.toggle("ico-link", isLocked);
        lockIcon.classList.toggle("ico-unlink", !isLocked);
		#end
	}
}

#end