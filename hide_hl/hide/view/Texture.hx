package hide.view;
import hrt.ui.*;

#if hui
private class TextureViewerShader extends hxsl.Shader {

	static var SRC = {

		@param var compressedTex : Sampler2D;
		@param var uncompressedTex : Sampler2D;
		@param var textureCube : SamplerCube;
		@param var textureArray : Sampler2DArray;
		@param var layer : Float;
		@param var mipLod : Float;
		@param var exposure : Float;
		@param var comparisonFactor : Float;

		@const var channels : Int;
		@const var isCube : Bool;
		@const var isArray : Bool;

		var pixelColor : Vec4;
		var calculatedUV : Vec2;
		var transformedNormal : Vec3;

		function fragment() {
			if( isCube )
				pixelColor = textureCube.getLod(transformedNormal, mipLod);
			else if( isArray )
				pixelColor = textureArray.getLod(vec3(calculatedUV, layer), mipLod);
			else {
				if (calculatedUV.x > comparisonFactor)
					pixelColor = uncompressedTex.getLod(calculatedUV, mipLod);
				else
					pixelColor = compressedTex.getLod(calculatedUV, mipLod);
			}
			pixelColor.rgb *= pow(2, exposure);
			switch( channels ) {
			case 0, 15:
				// nothing
			case 1:
				pixelColor = vec4(pixelColor.rrr, 1.);
			case 2:
				pixelColor = vec4(pixelColor.ggg, 1.);
			case 4:
				pixelColor = vec4(pixelColor.bbb, 1.);
			case 8:
				pixelColor = vec4(pixelColor.aaa, 1.);
			default:
				if( channels & 1 == 0 ) pixelColor.r = 0;
				if( channels & 2 == 0 ) pixelColor.g = 0;
				if( channels & 4 == 0 ) pixelColor.b = 0;
				if( channels & 8 == 0 ) pixelColor.a = 1;
			}
		}

	}

}

class Texture extends HuiView<{path: String}> {
	static var SRC = <texture>
		
	</texture>

	static var _ = HuiView.register("texture", Texture);

	static var TRANSPARENT_TEX_PATH = 'ui/transparent_tiles_dark.png';
	
	public var bmp : h2d.Bitmap;
	// public var camCtrl : h2d.CameraController;
	var shader : TextureViewerShader;

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		this.backgroundType = "hui";
		var tex = HuiRes.loader.load(TRANSPARENT_TEX_PATH).toImage().toTexture();
		tex.wrap = Repeat;
		this.huiBg.setTexture(tex);
		this.huiBg.imageMode = CssParser.BackgroundImageMode.Repeat;
		var tex = HuiRes.loader.load(TRANSPARENT_TEX_PATH).toImage().toTexture();

		shader = new TextureViewerShader();

		load(state.path);

		// camCtrl = new h2d.CameraController(this);

		buildToolbar();
	}

	override function getViewName():String {
		return state.path.split("/").splice(-1, 2).join("/");
	}

	override function requestClose(cb: (canClose:Bool) -> Void) {
		if (hasUnsavedChanges) {
			uiBase.confirm("Save change before closing ?", Save | DontSave | Cancel, (choice: hrt.ui.HuiConfirmPopup.ConfirmButton) -> {
				switch (choice) {
					case Save:
						execCommand(HuiCommands.save);
						cb(true);
					case DontSave:
						cb(true);
					case Cancel:
						cb(false);
					default:
						throw "???";
				}
			});
		} else {
			cb(true);
		}
	}

	override function getToolbarWidgets() : Array<HuiElement> {
		var widgets : Array<HuiElement> = [];

		var helpBtn = new HuiButton();
		helpBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiHelpPopup(this.registeredCommands), { object: Element(helpBtn), directionX: StartInside, directionY: EndOutside });
		};
		
		var compressedBtn = new HuiToggle();
		compressedBtn.dom.addClass("group-start");
		compressedBtn.toggled = true;
		new HuiIcon("raw_off", compressedBtn);
		widgets.push(compressedBtn);

		var uncompressedBtn = new HuiToggle();
		uncompressedBtn.dom.addClass("group");
		new HuiIcon("raw", uncompressedBtn);	
		widgets.push(uncompressedBtn);

		var compareBtn = new HuiToggle();
		compareBtn.dom.addClass("group-end");
		new HuiIcon("compare", compareBtn);	
		widgets.push(compareBtn);

		compressedBtn.onClick = (_) -> {
			if (compressedBtn.toggled) return;
			compressedBtn.toggled = !compressedBtn.toggled;
			uncompressedBtn.toggled = false;
			compareBtn.toggled = false;
			shader.comparisonFactor = 1;
		}

		uncompressedBtn.onClick = (_) -> {
			if (uncompressedBtn.toggled) return;
			uncompressedBtn.toggled = !uncompressedBtn.toggled;
			compressedBtn.toggled = false;
			compareBtn.toggled = false;
			shader.comparisonFactor = 0;
		}

		compareBtn.onClick = (_) -> {
			if (compareBtn.toggled) return;
			compareBtn.toggled = !compareBtn.toggled;
			uncompressedBtn.toggled = false;
			compressedBtn.toggled = false;
		}

		var rChannelBtn = new HuiToggle();
		rChannelBtn.toggled = true;
		rChannelBtn.dom.addClass("group-start");
		new HuiText("R", rChannelBtn);
		rChannelBtn.onClick = (_) -> {
			rChannelBtn.toggled = !rChannelBtn.toggled;
			setChannelVisible(0, rChannelBtn.toggled);
		}
		widgets.push(rChannelBtn);

		var gChannelBtn = new HuiToggle();
		gChannelBtn.toggled = true;
		gChannelBtn.dom.addClass("group");
		new HuiText("G", gChannelBtn);
		gChannelBtn.onClick = (_) -> {
			gChannelBtn.toggled = !gChannelBtn.toggled;
			setChannelVisible(1, gChannelBtn.toggled);
		}
		widgets.push(gChannelBtn);

		var bChannelBtn = new HuiToggle();
		bChannelBtn.toggled = true;
		bChannelBtn.dom.addClass("group");
		new HuiText("B", bChannelBtn);
		bChannelBtn.onClick = (_) -> {
			bChannelBtn.toggled = !bChannelBtn.toggled;
			setChannelVisible(2, bChannelBtn.toggled);
		}
		widgets.push(bChannelBtn);

		var aChannelBtn = new HuiToggle();
		aChannelBtn.toggled = true;
		aChannelBtn.dom.addClass("group-end");
		new HuiText("A", aChannelBtn);
		aChannelBtn.onClick = (_) -> {
			aChannelBtn.toggled = !aChannelBtn.toggled;
			setChannelVisible(3, aChannelBtn.toggled);
		}
		widgets.push(aChannelBtn);

		new HuiIcon("question_mark", helpBtn);
		widgets.push(helpBtn);

		return widgets;
	}

	function load(path : String) {
		if (bmp == null) {
			bmp = new h2d.Bitmap(null, this);
			bmp.addShader(shader);
			for (idx in 0...4)
				setChannelVisible(idx, true);
			shader.comparisonFactor = 1;
		}

		var compressedTex = hxd.res.Loader.currentInstance.load(Ide.inst.getRelPath(path)).toImage().toTexture();
		bmp.tile = h2d.Tile.fromTexture(compressedTex);
		
		var bytes = sys.io.File.getBytes(path);
		var uncompressedTex = hxd.res.Any.fromBytes(path, bytes).toImage().toTexture();

		shader.compressedTex = compressedTex;
		shader.uncompressedTex = uncompressedTex;
	}

	function setChannelVisible(channelIdx : Int, visible : Bool) {
		shader.channels &= ~(1 << channelIdx);
		if (visible) shader.channels |= 1 << channelIdx;
	}
}
#end