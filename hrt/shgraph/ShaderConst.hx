package hrt.shgraph;

using hxsl.Ast;

class ShaderConst extends ShaderNode {

	@prop() public var name : String = "";

	override function generate(ctx:NodeGenContext) {

	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);

		var element = new hide.Element('<div class="sg-const-name" style="width: ${width-16}px; height: 20px"></div>');

		var editBtn = new hide.Element('<fancy-button class="quieter compact"><div class="ico ico-pencil"></div></fancy-button>');

		element.append(editBtn);

		var input = new hide.Element('<input class="sg-const-name" type="text" id="value" placeholder="Name" value="${this.name}" autocomplete="off" />');

		element.append(input);

		input.on("keydown", function(e) {
			e.stopPropagation();
		});
		input.on("change", function(e) {
			this.name = input.val();
		});

		editBtn.on("click", function(e) {
			input.focus();
			input.select();
		});

		elements.push(element);

		return elements;
	}
	#end
}