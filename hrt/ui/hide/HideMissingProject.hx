package hrt.ui.hide;

#if hui

class HideMissingProject extends HuiElement {
	static var SRC = <hide-missing-project>
		<hui-text("No current project")/>
		<hui-button onClick={chooseProject}>
			<hui-text("Open project ...")/>
		</hui-button>
	</hide-missing-project>

	function chooseProject(e: hxd.Event) {
		hide.Ide.inst.chooseProject();
	}
}

#end