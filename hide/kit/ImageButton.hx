package hide.kit;

#if domkit

class ImageButton extends Button {
	public function new(parent: Element, id: String, image: String) {
		super(parent, id, "");
		this.image = image;
	}
}

#end