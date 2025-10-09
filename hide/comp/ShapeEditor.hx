package hide.comp;

enum Shapes {
	Box(width: Float, height: Float);
	Sphere(radius: Float);
}

class ShapeEditor extends Component {

	public function new(?parent: Element) {
    	super(parent, new Element('<div id="shape-editor">
			<label>Shape</label>
			<select>
				<option value="">Toto</option>
			</select>
			<label>Edit Shape</label>
			<button><div class="icon ico ico-pencil"></div></button>
		</div>'));
	}
}
