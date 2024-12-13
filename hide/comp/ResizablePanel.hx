package hide.comp;

enum LayoutDirection {
	Horizontal;
	Vertical;
}

enum SplitterPosition {
	Before;
	After;
}

class ResizablePanel extends hide.comp.Component {

	var layoutDirection : LayoutDirection;
	var splitterPosition : SplitterPosition;

	public function new(layoutDirection : LayoutDirection, element : Element, splitterPosition : SplitterPosition = Before) {
		super(null, element);
		this.layoutDirection = layoutDirection;
		this.splitterPosition = splitterPosition;
		var splitter = new Element('<div class="splitter"><div class="drag-handle"></div></div>');
		switch (layoutDirection) {
			case Horizontal:
				splitter.addClass("horizontal");
			case Vertical:
				splitter.addClass("vertical");
		}

		if (splitterPosition == Before)
			splitter.insertBefore(element);
		else
			splitter.insertAfter(element);
		
		var handle = splitter.find(".drag-handle").first();
		var drag = false;
		var startSize = 0;
		var startPos = 0;
		handle.mousedown((e) -> {
			drag = true;
			startSize = Std.int(layoutDirection == Horizontal? element.width() : element.height());
			startPos = layoutDirection == Horizontal? e.clientX : e.clientY;
		});
		handle.mouseup((e) -> drag = false);
		handle.dblclick((e) -> {
			setSize(Std.parseInt(element.css("min-width")));
		});
		var scenePartition = element.parent();
		scenePartition.mousemove((e) -> {
			if (drag){
				var newSize = 0;
				if (splitterPosition == Before)
					newSize = startSize - ((layoutDirection == Horizontal? e.clientX : e.clientY) - startPos);
				else 
					newSize = startSize + ((layoutDirection == Horizontal? e.clientX : e.clientY) - startPos);

				setSize(newSize);
			}
		});
		scenePartition.mouseup((e) -> {
			drag = false;
		});
		scenePartition.mouseleave((e) -> {
			drag = false;
		});
	}

	public function setSize(?newSize : Int) {
		onBeforeResize();
		
		var minSize = (layoutDirection == Horizontal? Std.parseInt(element.css("min-width")) : Std.parseInt(element.css("min-height")));
		var maxSize = (layoutDirection == Horizontal? Std.parseInt(element.css("max-width")) : Std.parseInt(element.css("max-height")));
		var clampedSize = 0;
		if (newSize !=  null) clampedSize = hxd.Math.iclamp(newSize, minSize, maxSize);
		else clampedSize = hxd.Math.iclamp(getDisplayState("size"), minSize, maxSize);
		switch (layoutDirection) {
			case Horizontal :
				element.width(clampedSize == null ? newSize : clampedSize);
			case Vertical :
				element.height(clampedSize == null ? newSize : clampedSize);
		}
		if (newSize != null) saveDisplayState("size", clampedSize == null ? newSize : clampedSize);

		onResize(); //@:privateAccess if( scene.window != null) scene.window.checkResize();
	}

    public dynamic function onBeforeResize() {}
    public dynamic function onResize() {}
}