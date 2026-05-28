package hide.kit;

#if domkit

class Texture extends Widget<Dynamic> {
	#if js
	var textureChoice: hide.comp.TextureChoice2;
	#elseif hui
	var textureChoice: hrt.ui.HuiTextureChoice;
	#end

	function makeInput() : NativeElement {
		#if js
		textureChoice = new hide.comp.TextureChoice2();
		textureChoice.onChange = (shoudSaveUndo) -> {
			value = textureChoice.value;
			broadcastValueChange(!shoudSaveUndo);
		}

		return textureChoice.element[0];
		#else
		textureChoice = new hrt.ui.HuiTextureChoice();
		textureChoice.onValueChange = (temp) -> {
			value = textureChoice.value;
			broadcastValueChange(temp);
		}

		return textureChoice;
		#end
		return null;
	}

	override function syncValueUI() {
		#if (js || hui)
		if (textureChoice != null)
			textureChoice.value = value;
		#end
	}

	function getDefaultFallback() : Dynamic {
		return null;
	}

	function stringToValue(obj: String) : Dynamic {
		var parsedData = try {
			haxe.Json.parse(obj);
		} catch(e) {
			return null;
		}
		if (hrt.impl.TextureType.Utils.getTextureType(obj) != null) {
			return obj;
		}
		return null;
	}
}

#end