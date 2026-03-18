package hrt.tools;

typedef Action = (isUndo: Bool) -> Void;

class Undo {
	var stack : Array<Action> = [];
	var currentAction : Int = -1;

	public function new() {

	}

	public function record(action: Action) {
		stack.splice(currentAction+1, stack.length);
		stack.push(action);
		currentAction = stack.length-1;
	}

	public function undo() {
		if (canUndo()) {
			stack[currentAction](true);
			currentAction--;
		}
	}

	public function canUndo() {
		return currentAction >= 0;
	}

	public function redo() {
		if (canRedo()) {
			currentAction++;
			stack[currentAction](false);
		}
	}

	public function canRedo() {
		return currentAction < stack.length -1;
	}
}