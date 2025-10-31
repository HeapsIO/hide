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
	@:s var vector4: h3d.Vector4 = new h3d.Vector4();
	@:s var category: Bool = false;

	@:s var advancedDetails: Bool;
	@:s var dynamicArray: Array<Int> = [];
	var substruct: SubStruct = { innerValue: 0.0, };

	override function edit2(ctx:hrt.prefab.EditContext2) {
		ctx.build(
			<category("All Elements")>
				<text("Text")/>
				<slider label="Slider" value={12.34}/>
				<slider label="Disabled slider" value={12.34} disabled/>
				<slider label="Slider Exp" value={12.34} exp step={0.001}/>
				<slider label="Slider Exp Custom" value={12.34} exp step={0.0001}/>
				<slider label="Slider Poly" value={12.34} poly step={0.001}/>
				<slider label="Slider Poly Custom" value={12.34} poly={1.5} step={0.001}/>
				<range(0.0, 100.0) label="Range" value={12.34}/>
				<range(0,100) label="Range Int" value={12} int/>
				<range(0.001, 1000.0) label="Range Exp" value={12.34} exp step={0.01}/>
				<range(0.001, 1000.0) label="Range Poly" value={12.34} poly step={0.01}/>
				<line>
					<slider label="A" value={12.34}/>
					<slider label="B" value={12.34}/>
				</line>
				<text("Separator")/>
				<separator/>
				<file field={filePath} type="texture"/>
				<button("Button")/>
				<button("Button Highlight") highlight/>
				<button("Button Disabled") disabled/>
				<button("Button Single Edit") single-edit/>
				<input label="Input" placeholder="Placeholder text" field={inputString}/>
				<color field={color}/>
				<gradient field={gradient}/>
				<texture field={texture}/>
				<select(["Fire", "Earth", "Water", "Air"]) field={select} />
				<checkbox field={checkbox}/>

				<line>
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

		parentLine.build(<image-button("textures/dirt01.jpg") big/>, null);
		parentLine.build(<image-button("textures/dirt01.jpg") big/>, null);
		parentLine.build(<image-button("textures/dirt01.jpg") big/>, null);
		parentLine.build(<image-button("textures/dirt01.jpg") big/>, null);
		parentLine.build(<image-button("textures/dirt01.jpg") big/>, null);

		for (i in 0...3) {
			addToMe.build(<button({'$i';}) id="button"/>, null);
			button.onClick = () -> trace('onclick $i');
		}

		// GENERAL API
		{
			// Assigning an explicit id to an element will make it available inside this scope
			// You can call build on a hide.kit.Element to add more element with DML
			ctx.build(
				<category("Element") id="category"></category>
			);

			// Assigning an explicit id to an element will make it available inside this scope
			category.build(<button("Button") id="button"/>);
			button.onClick = () -> {trace("Button clicked");};

			// If for some reason you want an element to not be interactible, you can set it to `disabled`
			category.build(<button("Disabled") disabled/>);


			// Some element shouldn't be edited if multiple elements are selected in the editor. This is
			// especially important for button that can do operations on things other than the prefab there are linked to (like modifying the scene for example)
			// In that case, setting the single-edit attribute will disable that element and all of it's children
			// when more than one prefab is selected
			category.build(<button("Single Edit") single-edit/>);
		}

		// CATEGORIES
		{
			ctx.build(
				<root>
					<category("Basic Category")>
						<text("This is an element inside a category")/>
					</category>
					<category("Default colapsed category") closed>
						<text("This category defaults to a closed state by default")/>
					</category>
					<category("Value category") field={category}>
						<text("This category is bound to a field/value and displays a checkbox that allow to set this value. All of its content are disabled if the value is false")/>
						<slider/>
						<button("Button")/>
						<category("Nested value category") value={false}>
							<text("This category should be disabled when its parent value is set to false")/>
							<button("Button")/>
						</category>
					</category>
					<category("Nested category")>
						<category("Child 1")>
							<button("Button")/>
						</category>
						<category("Child 2")>
							<button("Button")/>
						</category>
					</category>
				</root>
			);
		}


		// SLIDER / RANGES
		{
			ctx.build(
				<root>
					<category("Slider")>
						<slider label="Basic" value={10} id="basic" /> // Bind later with id
						<slider field={x}/> // Bind to a class field
						<slider label="Min/max" value={10} min={0} max={100} /> // Min max
						<slider label="Wrap" value={10} min={0} max={100} wrap/> // Wrap around
						<slider label="Exp" value={10} exp wrap/> // Exponential curve
						<slider label="Poly" value={10} poly wrap/> // Polynomial curve
						<slider label="Int" value={10} int/> // Int Slider

						<separator/>
						<text("A slider group add a little \"link\" button that allow one slider to change all the other sliders proportionally")/>
						<slider-group label="Group">
							<slider label="A" value={10}/>
							<slider label="B" value={20}/>
							<slider label="C" value={30}/>
						</slider-group>
					</category>
					<category("Range")>
						<text("Ranges are basically an alias for a slider with a mandatory min/max")/>
						<range(0.0, 100.0) label="Range" value={12.34}/>
						<range(0,100) label="Range Int" value={12} int/>
						<range(0.001, 1000.0) label="Range Exp" value={12.34} exp/>
						<range(0.001, 1000.0) label="Range Poly" value={12.34} poly/>
					</category>
				</root>
			);

			basic.onValueChange = (temp: Bool) -> {
				trace(basic.value, temp);
			};
		}

		// TEXT
		{
			ctx.build(
				<category("Text")>
					<text("This is a text element example")/>
				</category>
			);
		}

		// LINES
		{
			ctx.build(
				<category("Lines")>
					<line label="Two">
						<slider label="A"/>
						<slider label="B"/>
					</line>
					<line label="Three">
						<slider label="A"/>
						<slider label="B"/>
						<slider label="C"/>
					</line>
					<line label="Four">
						<slider label="A"/>
						<slider label="B"/>
						<slider label="C"/>
						<slider label="D"/>
					</line>

					// Full lines don't reserve space for their label to the left of the editor
					<line full>
						<slider label="A"/>
						<slider label="B"/>
						<slider label="C"/>
						<slider label="D"/>
					</line>
					<line label="Mix">
						<slider label="A"/>
						<button("B")/>
						<select(["A", "B", "C"]) label="C"/>
					</line>

					<line label="Multiline" multiline>
						<slider label="A"/>
						<slider label="B"/>
						<slider label="C"/>
						<slider label="D"/>
						<slider label="E"/>
						<button("Big Button") big/>
						<button("Big Button") big/>
					</line>

					<line label="Disabled" disabled>
						<slider label="A"/>
						<slider label="B"/>
						<slider label="C"/>
						<slider label="D"/>
					</line>
				</category>
			);
		}

		// BUTTONS
		{
			function onButtonClick() {
				hide.Ide.inst.quickMessage("Button clicked");
			}

			ctx.build(
				<category("Buttons")>
					<button("Simple Button") id="simpleButton"/> // bind via ID
					<button("Inline onClick") onClick={() -> hide.Ide.inst.quickMessage("Inline Button clicked")}/> // Bind with an inline function
					<button("Direct bind onClick") onClick={onButtonClick}/> // Bind with a function
					<button("Highlight") highlight/>
					<button("Disabled") disabled/>
					<button("Single Edit") single-edit/>
				</category>
			);

			simpleButton.onClick = onButtonClick;
		}

		// INPUT
		{
			ctx.build(
				<category("Input")>
					<input label="Input"/>
					<input placeholder="Insert your text here" label="Placehodler"/>
				</category>
			);
		}

		// SELECT
		{
			function generator() {
				return [for (i in 0...10) {value: i, label: '$i'}];
			}

			ctx.build(
				<category("Select")>
					<select(["Earth", "Wind", "Fire", "Water"]) label="Strings" value={"Earth"}/>
					<select([{value: 0, label: "Earth"}, {value: 1, label: "Wind"}, {value: 2, label: "Fire"}, {value: 3, label: "Water"}]) label="Objects" value={0}/>
					<select(generator()) label="From Generator" value={0}/>
				</category>
			);
		}

		// COLOR
		{
			ctx.build(
				<category("Color")>
					<color value={0xFF00FF} label="Color"/>
					<color value={0x88FF00FF} alpha label="With Alpha"/>
					<color field={vector4} label="Vec4"/>
				</category>
			);
		}

		// Dynamic UI example
		{
			ctx.build(
				<category("Dynamic UI")>
					// Use a checkbox to "dynamicaly hide elements using a if() statement".
					// To make the UI dynamic, we need to call ctx.rebuildInspector() when the value is changed
					<checkbox field={advancedDetails} onValueChange={(tmp) -> ctx.rebuildInspector()}/>
					<slider label="Advanced setting" if(advancedDetails)/>

					// We can also use the disabled attribute instead of hiding the element to avoid UI shifts
					<slider label="Enabled if advanced" disabled={!advancedDetails}/>
					<separator/>
					<text("Array editor example")/>

					// Here is an example of an array editor done only with the basic kit elements
					// we use a block element to later add elements in a for loop. The block element
					// is an element that doesn't create anything in the final layout
					<block id="arrayEdit">

					</block>
					<line><button("Add one") id="addOne"/><button("Clear") id="clear"/></line>
				</category>
			);

			// Here we build the rest of the Array editor
			// Undo redo is magically supported because dynamicArray is a @:s field in this prefab !
			for (i => value in dynamicArray) {
				arrayEdit.build(
					<line label={'$i'}>
						// We can use an array+index as a field !
						<slider field={dynamicArray[i]} label=""/>
						<button("-") id="sub"/>
						<button("+") id="plus"/>
						<button("Delete") id="delete"/>
					</line>
				);

				sub.onClick = () -> {
					dynamicArray[i] --;
					// Don't forget to refresh the UI to refresh the slider
					ctx.rebuildInspector();
				}

				plus.onClick = () -> {
					dynamicArray[i] ++;
					ctx.rebuildInspector();
				}

				delete.onClick = () -> {
					dynamicArray.splice(i, 1);
					ctx.rebuildInspector();
				}
			}

			addOne.onClick = () -> {
				dynamicArray.push(0);
				ctx.rebuildInspector();
			}

			clear.onClick = () -> {
				dynamicArray.resize(0);
				ctx.rebuildInspector();
			}
		}
	}

	@:keep
	function compilationTests() {
		hide.kit.Macros.testError(
			"not a dml expression", this, "dml argument should be a DML Expression"
		);

		hide.kit.Macros.testError(
			<unknown-component/>, this, "hide-kit element hide.kit.UnknownComponent doesn't exist"
		);

		hide.kit.Macros.testError(
			<native-element/>, this, "type hide.kit.NativeElement is not a class"
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

		hide.kit.Macros.testError(
			<root>
				<range id="a"/>
				<range id="a"/>
			</root>
		, this, "A component with the id a already exists in this build");

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
			<range field="x"/>, this, "field must be an identifier,structure field or array expression"
		);

		hide.kit.Macros.testError(
			<range field={123}/>, this, "field must be an identifier,structure field or array expression"
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
			<range unknown-attribute="true"/>, this, "hide.kit.Range has no attribute named unknownAttribute"
		);

		hide.kit.Macros.testError(
			<range unknown-attribute/>, this, "hide.kit.Range has no attribute named unknownAttribute"
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

	#if editor
	override function getHideProps():Null<hide.prefab.HideProps> {
		return {
			name: "Kit Test",
			icon: "question-cicle",
		}
	}
	#end

	static var _ = hrt.prefab.Prefab.register("kitTest", KitTest);
}