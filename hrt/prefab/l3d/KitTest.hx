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
				var cat = new hide.kit.Category(root, root, "widgets", "Widgets");
				{
					var text = new hide.kit.Text(root, cat, null, "Text");
					var slider = new hide.kit.Slider(root, cat, "x"); slider.label = "x"; slider.value = x; slider.onValueChange = (temp) -> {
						this.x = slider.value;
						updateInstance("x");
					};
					var slider = new hide.kit.Slider(root, cat, "y"); slider.label = "y"; slider.value = y; slider.onValueChange = (temp) -> {
						this.y = slider.value;
						updateInstance("y");
					};
					var slider = new hide.kit.Slider(root, cat, "z"); slider.label = "z"; slider.value = z; slider.onValueChange = (temp) -> {
						this.z = slider.value;
						updateInstance("z");
					};


					var range = new hide.kit.Range(root, cat, "slider", 0.0, 100.0); range.label = "Slider"; range.value = 12.34;

					var line = new hide.kit.Line(root, cat, null); line.label = "Line";
					{
						var slider = new hide.kit.Range(root, line, "sliderA", 0, 100); slider.label = "A"; slider.value = 12.34;
						var slider = new hide.kit.Range(root, line, "sliderB", 0, 100); slider.label = "B"; slider.value = 12.34;
					}
					var text = new hide.kit.Text(root, cat, null, "Separator");
					var separator = new hide.kit.Separator(root, cat, null);
					var file = new hide.kit.File(root, cat, null); file.label="File"; file.type = "texture";
				}

				var cat = new hide.kit.Category(root, root, "test", "Layout");
				{
					var text = new hide.kit.Text(root, cat, null, "Hello world");
					var slider = new hide.kit.Slider(root, cat, "slider"); slider.label = "Slider"; slider.value = 12.34;
					var slider = new hide.kit.Slider(root, cat, "slider2"); slider.label = "Another Slider"; slider.value = 12.34;
					var separator = new hide.kit.Separator(root, cat, null);
					var slider = new hide.kit.Slider(root, cat, "slider2"); slider.label = "Another Slider"; slider.value = 12.34;
					var slider = new hide.kit.Slider(root, cat, "slider3"); slider.label = "Another Slider With a Long Name"; slider.value = 12.34;

					var line = new hide.kit.Line(root, cat, null);
					{
						var slider = new hide.kit.Slider(root, line, "sliderA"); slider.label = "A"; slider.value = 12.34;
						var slider = new hide.kit.Slider(root, line, "sliderB"); slider.label = "B"; slider.value = 12.34;
					}

					var line = new hide.kit.Line(root, cat, null); line.label = "Position";
					{
						var slider = new hide.kit.Slider(root, line, "sliderX"); slider.value = 12.34;
						var slider = new hide.kit.Slider(root, line, "sliderY"); slider.value = 12.34;
						var separator = new hide.kit.Separator(root, line, null);
						var slider = new hide.kit.Slider(root, line, "sliderZ"); slider.value = 12.34;
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