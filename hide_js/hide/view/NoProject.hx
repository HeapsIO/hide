package hide.view;

class NoProject extends hide.ui.View<{}> {

	override function onDisplay() {
		var root = element.get(0);
		root.classList.add("no-project");

		hide.html.Html.build(root,
			<div class="no-project-content">
				<span>No current project</span>
				<button onclick={() -> @:privateAccess ide.chooseProject()}>Open project ...</button>
			</div>
		);
	}

	override function getTitle() {
		return "No Project";
	}

	static var _ = hide.ui.View.register(NoProject);

}
