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

	@:s var inputString : String;
	@:s var filePath : String;
	@:s var color : Int;
	@:s var gradient : hrt.impl.Gradient.GradientData;
	@:s var select : String;
	@:s var checkbox: Bool;

	#if js
	override function edit2(ctx:hide.prefab.EditContext) {
		// TEST
		{

			trace("start of test macro");


			hide.kit.Macros.build(ctx.properties2,
				<category("hello") id="hello">
					<text("world")/>
					<slider label="Slider" id="slider" min="-10" max="10"/>
				</category>, this
			);

			trace("end of test macro");

			// ==>

			// var hello : hide.kit.Category;
			// {
			// 	var parent = ctx.properties2;
			// 	hello = new hide.kit.Category(parent, "hello", "hello");
			// 	{
			// 		parent = hello;
			// 		var text = new hide.kit.Category(parent, null, "world");
			// 	}
			// }

			// // le code extérieur peut maintenant manipuler hello
			// hello.addChild(...);

			// hide.kit.Macros.build(ctx.properties2,
			// 	<element>
			// 	</element>, this
			// );

			var root = @:privateAccess ctx.properties2;
			{
				var cat = new hide.kit.Category( root, "testEditor", "Test Editor");
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
				}

				var cat = new hide.kit.Category(root, "elements", "All Elements");
				{
					var text = new hide.kit.Text( cat, null, "Text");
					var slider = new hide.kit.Slider( cat, "slider"); slider.label = "Slider"; slider.value = 12.34;
					var range = new hide.kit.Range( cat, "range", 0.0, 100.0); range.label = "Range"; range.value = 12.34;

					var line = new hide.kit.Line( cat, null); line.label = "Line";
					{
						var slider = new hide.kit.Range( line, "sliderA", 0, 100); slider.label = "A"; slider.value = 12.34;
						var slider = new hide.kit.Range( line, "sliderB", 0, 100); slider.label = "B"; slider.value = 12.34;
					}
					var text = new hide.kit.Text( cat, null, "Separator");
					var separator = new hide.kit.Separator( cat, null);
					var file = new hide.kit.File( cat, "file"); file.label="File"; file.type = "texture"; file.value = filePath; file.onValueChange = (temp) -> {
						filePath = file.value;
					};
					var button = new hide.kit.Button(cat, "button", "Button");
					var button = new hide.kit.Button(cat, "buttonHighlight", "Button Highlight"); button.highlight = true;

					var input = new hide.kit.Input(cat, null); input.placeholder = "Placeholder text"; input.label="Input"; input.value = inputString; input.onValueChange = (temp) -> {
						inputString = input.value;
					};
					var color = new hide.kit.Color(cat, "color"); color.label="Color"; color.value = this.color; color.onValueChange = (temp) -> {
						this.color = color.value;
					}

					var gradient = new hide.kit.Gradient(cat, "gradient"); gradient.label="Gradient"; gradient.value = this.gradient; gradient.onValueChange = (temp) -> {
						this.gradient = gradient.value;
					}

					var select = new hide.kit.Select(cat, "select", ["Fire", "Earth", "Water", "Air"]); select.label = "Select"; select.value = this.select; select.onValueChange = (temp) -> {
						this.select = select.value;
					};

					var checkbox = new hide.kit.Checkbox(cat, "checkbox"); checkbox.label="Checkbox"; checkbox.value = this.checkbox; checkbox.onValueChange = (temp) -> {
						this.checkbox = checkbox.value;
					};
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

					var line = new hide.kit.Line(cat, "checkboxes"); line.label = "Checkboxes";
					{
						for (i in 0...8) {
							var cb = new hide.kit.Checkbox(line, 'cb$i');
						}
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