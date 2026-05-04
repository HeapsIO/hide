package hrt.tools;

typedef Action = (isUndo: Bool) -> Void;

class Undo {
	var stack : Array<{action: Action, hasDataChanges: Bool}> = [];
	var currentAction : Int = -1;

	public function new() {

	}

	public function record(action: Action, hasDataChanges: Bool) {
		stack.splice(currentAction+1, stack.length);
		stack.push({action: action, hasDataChanges: hasDataChanges});
		currentAction = stack.length-1;
		onAfterChange();
	}

	public function run(action: Action, hasDataChanges: Bool) {
		if (action == null)
			return;
		action(false);
		record(action, hasDataChanges);
	}

	public dynamic function onAfterChange() {

	}

	public function undo() {
		if (canUndo()) {
			stack[currentAction].action(true);
			currentAction--;
			onAfterChange();
		}
	}

	public function canUndo() {
		return currentAction >= 0;
	}

	public function redo() {
		if (canRedo()) {
			currentAction++;
			stack[currentAction].action(false);
			onAfterChange();
		}
	}

	public function canRedo() {
		return currentAction < stack.length -1;
	}

	/**
		Return the current active undo function (i.e. the one what would be executed if when calling Undo)
	**/
	public function getCurrentUndo() : Any {
		return stack[currentAction];
	}

	public function hasDataChanges(otherUndo: Any) : Bool {
		var current = currentAction;
		while(current >= -1) {
			if (stack[current] != otherUndo && stack[current]?.hasDataChanges == true)
				return true;
			else if (stack[current] == otherUndo)
				return false;
			current --;
		}
		return true;
	}
}