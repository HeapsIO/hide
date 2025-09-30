package hrt.prefab.l3d;

class KitTest extends Object3D {

	#if js
	override function edit(ctx:hide.prefab.EditContext) {
		// TEST
		{
			var root = new hide.kit.Element(ctx, null, "");
			ctx.properties.element[0].append(@:privateAccess root.wrap);
			{
				var cat = new hide.kit.Category(ctx, root, "test", "Test");
				{
					var text = new hide.kit.Text(ctx, cat, null, "Hello world");
					var slider = new hide.kit.Slider(ctx, cat, "slider"); slider.label = "Slider"; slider.value = 12.34;
					var slider = new hide.kit.Slider(ctx, cat, "slider2"); slider.label = "Another Slider"; slider.value = 12.34;
					var slider = new hide.kit.Slider(ctx, cat, "slider3"); slider.label = "Another Slider With a Long Name"; slider.value = 12.34;

					var line = new hide.kit.Line(ctx, cat, null);
					{
						var slider = new hide.kit.Slider(ctx, line, "sliderA"); slider.label = "A"; slider.value = 12.34;
						var slider = new hide.kit.Slider(ctx, line, "sliderB"); slider.label = "B"; slider.value = 12.34;
					}

					var line = new hide.kit.Line(ctx, cat, null); line.label = "Position";
					{
						var slider = new hide.kit.Slider(ctx, line, "sliderX"); slider.value = 12.34;
						var slider = new hide.kit.Slider(ctx, line, "sliderY"); slider.value = 12.34;
						var slider = new hide.kit.Slider(ctx, line, "sliderZ"); slider.value = 12.34;
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