package hide.comp;

enum LayoutDirection {
	Horizontal;
	Vertical;
}
class ResizablePanel extends hide.comp.Component {

	var layoutDirection : LayoutDirection;

	public function new(layoutDirection : LayoutDirection, element : Element) {
		super(null, element);
		this.layoutDirection = layoutDirection;
		var splitter = new Element('<div class="splitter"><div class="drag-handle"></div></div>');
		switch (layoutDirection) {
			case Horizontal:
				splitter.addClass("horizontal");
			case Vertical:
				splitter.addClass("vertical");
		}
		splitter.insertBefore(element);
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
				setSize(startSize - ((layoutDirection == Horizontal? e.clientX : e.clientY) - startPos));
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
		var minSize = (layoutDirection == Horizontal? Std.parseInt(element.css("min-width")) : Std.parseInt(element.css("min-height")));
		var maxSize = (layoutDirection == Horizontal? Std.parseInt(element.css("max-width")) : Std.parseInt(element.css("max-height")));
		var clampedSize = 0;
		if (newSize !=  null) clampedSize = hxd.Math.iclamp(newSize, minSize, maxSize);
		else clampedSize = hxd.Math.iclamp(getDisplayState("size"), minSize, maxSize);
		switch (layoutDirection) {
			case Horizontal :
				element.width(clampedSize);
			case Vertical :
				element.height(clampedSize);
		}
		if (newSize != null) saveDisplayState("size", clampedSize);

		onResize(); //@:privateAccess if( scene.window != null) scene.window.checkResize();
	}

    public dynamic function onResize() {}
}