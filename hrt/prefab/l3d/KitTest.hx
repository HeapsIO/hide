package hrt.prefab.l3d;

typedef SubStruct = {
	innerValue: Float,
	?rec: SubStruct,
};

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
	@:s var texture: Dynamic;
	var substruct: SubStruct = { innerValue: 0.0, };

	#if js
	override function edit2(ctx:hide.prefab.EditContext) {
		// TEST
		{



			trace("start of test macro");

			function getChoiceList() {
				return ["Alice", "Bob", "Charles"];
			}

			function onButtonClick() {
				trace("clicked");
			}


			var localVar = 42.0;
			ctx.build(
				<category("hello") id="hello">
					<text("world")/>
					<slider label="Slider" id="slider" min="-10" max="10"/>
					<slider label="Slider Conditional" id="slider-conditionnal" min="-10" max="10" if(inputString != null)/>
					<slider label="Slider Local" field={localVar}/>

					<select(["Fire", "Water", "Air", "Earth"]) label="Choice" id="choice"/>
					<select(getChoiceList()) label="Choice" id="choice2"/>
					<button("Click me") onClick={onButtonClick} id="button1"/>
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

			// ctx.build(ctx.properties2,
			// 	<element>
			// 	</element>, this
			// );

			ctx.build(
				<category("Test Editor Kit")>
					<slider field={x}/>
					<slider field={y}/>
					<slider field={z}/>
					<button("Reset") onClick={() -> {
						x = 0;
						y = 0;
						z = 0;
					}}/>
					<line id="line">
						<button("x2") onClick={() -> {
							x *= 2.0;
							y *= 2.0;
							z *= 2.0;
						}}/>
						<button("/2") onClick={() -> {
							x /= 2;
							y /= 2;
							z /= 2;
						}}/>
					</line>
				</category>
				,this
			);

			var root = @:privateAccess ctx.kitRoot;
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

				ctx.build(
					<category("All Elements Kit")>
						<text("Text")/>
						<slider label="Slider" value={12.34}/>
						<slider label="Slider Exp" value={12.34} exp={0.001}/>
						<range(0.0, 100.0) label="Range" value={12.34}/>
						<line>
							<slider label="A" value={12.34}/>
							<slider label="B" value={12.34}/>
						</line>
						<text("Separator")/>
						<separator/>
						<file field={filePath} type="texture"/>
						<button("Button")/>
						<button("Button Highlight") highlight/>
						<input label="Input" placeholder="Placeholder text" field={inputString}/>
						<color field={color}/>
						<gradient field={gradient}/>
						<texture field={texture}/>
						<select(["Fire", "Earth", "Water", "Air"]) field={select} />
						<checkbox field={checkbox}/>

						<line full>
							<image-button("ui/search.png") medium/>
							<image-button("ui/home.png") medium/>
							<image-button("ui/menu.png") medium/>
							<image-button("ui/close.png") medium/>
						</line>


						<line id="parentLine" multiline>
						</line>

						<block id="addToMe"></block>
					</category>,
				this);

				ctx.build(<image-button("textures/dirt01.jpg") big/>, null, parentLine);
				ctx.build(<image-button("textures/dirt01.jpg") big/>, null, parentLine);
				ctx.build(<image-button("textures/dirt01.jpg") big/>, null, parentLine);
				ctx.build(<image-button("textures/dirt01.jpg") big/>, null, parentLine);
				ctx.build(<image-button("textures/dirt01.jpg") huge/>, null, parentLine);
				ctx.build(<image-button("textures/dirt01.jpg") huge/>, null, parentLine);

				for (i in 0...5) {
					ctx.build(<button({'$i';}) id="button"/>, null, addToMe);
					button.onClick = () -> trace('onclick $i');
				}

				// uncomment this to test error "contextObj must be not null for `field` to work"
				// ctx.build(<slider field={foo}/>, null, parentGroup);

				// uncomment this to test error "contextObj doesn't have a field named foo"
				// ctx.build(<slider field={foo}/>, "bar", parentGroup);

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

					var texture = new hide.kit.Texture(cat, "texture"); texture.label="Texture"; texture.value = this.texture; texture.onValueChange = (_) -> this.texture = texture.value;

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

			// DML TESTS
			hide.kit.Macros.testError(
				"c'est pas du dml", this, "dml argument should be a DML Expression"
			);

			hide.kit.Macros.testError(
				<unknown-component/>, this, "hide-kit element hide.kit.UnknownComponent doesn't exist"
			);

			// LABEL RELATED TESTS

			hide.kit.Macros.testNoError(
				<range label="label"/>, this
			);

			{
				var monLabel = "label";
				hide.kit.Macros.testNoError(
					<range label={monLabel}/>, this
				);
			}

			hide.kit.Macros.testError(
				<range label={123}/>, this, "label value must be string expression or a string constant"
			);

			// Can't test this because the error is a hide error after the codegen pass is done
			// hide.kit.Macros.testError(
			// 	<range label={unknownVariable}/>, this, "label value must be string expression or a string constant"
			// );

			// ID Related tests

			hide.kit.Macros.testNoError(
				<range id="id"/>, this
			);

			hide.kit.Macros.testNoError(
				<range id={"id"}/>, this
			);

			// Id must be comptime known
			{
				var id = "id";
				hide.kit.Macros.testError(
					<range id={id}/>, this, "id value must be a const string"
				);
			}

			// Field related tests

			hide.kit.Macros.testNoError(
				<range field={x}/>, this
			);

			hide.kit.Macros.testNoError(
				<range field={this.x}/>, this
			);

			hide.kit.Macros.testNoError(
				<range field={substruct.rec.innerValue}/>, this
			);

			{
				var local : Float = 42.0;
				hide.kit.Macros.testNoError(
					<range field={local}/>, this
				);
			}

			hide.kit.Macros.testError(
				<range field="x"/>, this, "field must be an expression"
			);

			hide.kit.Macros.testError(
				<range field={123}/>, this, "field must be an identifier expression or a structure field expression"
			);

			// Attributes related tests

			// Parse string as correct type
			hide.kit.Macros.testNoError(
				<range min="0"/>, this
			);

			hide.kit.Macros.testError(
				<range min="notANumber"/>, this, 'cannot convert "notANumber" to Float for attribute min'
			);

			hide.kit.Macros.testError(
				<range unknown-attribute="true"/>, this, "unknown class field unknownAttribute"
			);

			hide.kit.Macros.testError(
				<range unknown-attribute/>, this, "unknown class field unknownAttribute"
			);

			hide.kit.Macros.testNoError(
				<line multiline/>, this,
			);

			hide.kit.Macros.testNoError(
				<line multiline="false"/>, this,
			);

			hide.kit.Macros.testNoError(
				<line multiline={true}/>, this,
			);

			{
				var local = true;
				hide.kit.Macros.testNoError(
					<line multiline={local}/>, this
				);
			}

			hide.kit.Macros.testNoError(
				<line multiline="true"/>, this,
			);

			hide.kit.Macros.testError(
				<line multiline="True"/>, this, 'cannot convert "True" to Bool for attribute multiline (must be either "true" or "false")'
			);
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