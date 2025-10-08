package hide.kit;

class Texture extends Widget<Dynamic> {
	var textureChoice: hide.comp.TextureChoice;

	function makeInput() : NativeElement {
		textureChoice = new hide.comp.TextureChoice();
		textureChoice.onChange = (shoudSaveUndo) -> {
			value = textureChoice.value;
			broadcastValueChange(!shoudSaveUndo);
		}

		return textureChoice.element[0];
	}

	override function syncValueUI() {
		#if js
		if (textureChoice != null)
			textureChoice.value = value;
		#end
	}
}