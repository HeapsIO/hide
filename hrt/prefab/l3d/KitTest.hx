package hrt.prefab.l3d;

class KitTest extends Object3D {

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		var mesh = new h3d.scene.Mesh(h3d.prim.Cube.defaultUnitCube(), parent3d);

		#if editor
		var wire = new h3d.scene.Box(mesh);
		wire.color = 0;
		wire.ignoreCollide = true;
		wire.material.shadows = false;
		#end

		return mesh;
	}

	#if js
	override function edit2(ctx:hide.prefab.EditContext) {
		// TEST
		{
			var root = @:privateAccess ctx.properties2;
			{
				var cat = new hide.kit.Category( root, "widgets", "Widgets");
				{
					var text = new hide.kit.Text( cat, null, "Text");
					var slider = new hide.kit.Slider( cat, "x"); slider.label = "X"; slider.value = x; slider.onValueChange = (temp) -> {
						x = slider.value;
					};
					var slider = new hide.kit.Slider( cat, "y"); slider.label = "Y"; slider.value = y; slider.onValueChange = (temp) -> {
						y = slider.value;
					};
					var slider = new hide.kit.Slider( cat, "z"); slider.label = "Z"; slider.value = z; slider.onValueChange = (temp) -> {
						z = slider.value;
					};

					var button = new hide.kit.Button( cat, "reset", "Reset"); button.onClick = () -> {
						x = 0;
						y = 0;
						z = 0;
					};

					var line =  new hide.kit.Line( cat, "operators");
					{
						var button = new hide.kit.Button( line, "mult", "x2"); button.onClick = () -> {
							x *= 2;
							y *= 2;
							z *= 2;
						}

						var button = new hide.kit.Button( line, "div", "/2"); button.onClick = () -> {
							x /= 2;
							y /= 2;
							z /= 2;
						}
					}


					var range = new hide.kit.Range( cat, "slider", 0.0, 100.0); range.label = "Slider"; range.value = 12.34;

					var line = new hide.kit.Line( cat, null); line.label = "Line";
					{
						var slider = new hide.kit.Range( line, "sliderA", 0, 100); slider.label = "A"; slider.value = 12.34;
						var slider = new hide.kit.Range( line, "sliderB", 0, 100); slider.label = "B"; slider.value = 12.34;
					}
					var text = new hide.kit.Text( cat, null, "Separator");
					var separator = new hide.kit.Separator( cat, null);
					var file = new hide.kit.File( cat, null); file.label="File"; file.type = "texture";
				}

				var cat = new hide.kit.Category( root, "test", "Layout");
				{
					var text = new hide.kit.Text( cat, null, "Hello world");
					var slider = new hide.kit.Slider( cat, "slider"); slider.label = "Slider"; slider.value = 12.34;
					var slider = new hide.kit.Slider( cat, "slider2"); slider.label = "Another Slider"; slider.value = 12.34;
					var separator = new hide.kit.Separator( cat, null);
					var slider = new hide.kit.Slider( cat, "slider2"); slider.label = "Another Slider"; slider.value = 12.34;
					var slider = new hide.kit.Slider( cat, "slider3"); slider.label = "Another Slider With a Long Name"; slider.value = 12.34;

					var line = new hide.kit.Line( cat, null);
					{
						var slider = new hide.kit.Slider( line, "sliderA"); slider.label = "A"; slider.value = 12.34;
						var slider = new hide.kit.Slider( line, "sliderB"); slider.label = "B"; slider.value = 12.34;
					}

					var line = new hide.kit.Line( cat, null); line.label = "Position";
					{
						var slider = new hide.kit.Slider( line, "sliderX"); slider.value = 12.34;
						var slider = new hide.kit.Slider( line, "sliderY"); slider.value = 12.34;
						var separator = new hide.kit.Separator( line, null);
						var slider = new hide.kit.Slider( line, "sliderZ"); slider.value = 12.34;
					}
				}
			}
		}
	}

	override function getHideProps():Null<hide.prefab.HideProps> {
		return {
			name: "Kit Test",
			icon: "question-cicle",
		}
	}

	#end

	static var _ = hrt.prefab.Prefab.register("kitTest", KitTest);
}