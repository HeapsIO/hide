package hide.kit;

class Texture extends Widget<Dynamic> {
	#if js
	var textureChoice: hide.comp.TextureChoice;
	#end

	function makeInput() : NativeElement {
		#if js
		textureChoice = new hide.comp.TextureChoice();
		textureChoice.onChange = (shoudSaveUndo) -> {
			value = textureChoice.value;
			broadcastValueChange(!shoudSaveUndo);
		}

		return textureChoice.element[0];
		#end
		return null;
	}

	override function syncValueUI() {
		#if js
		if (textureChoice != null)
			textureChoice.value = value;
		#end
	}

	function getDefaultFallback() : Dynamic {
		return null;
	}
}