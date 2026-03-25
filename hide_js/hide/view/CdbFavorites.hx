package hide.view;

class CdbFavorites extends hide.ui.View<> {
    var favorites: Array<RefViewer.Result> = [];
	public function new(state: Dynamic) {
		super(state);
	}

	override function getTitle() {
		return "Favorites";
	}

    public function addFavorite(result: RefViewer.Result) {
        for (f in favorites) {
            if (f.text == result.text)
                return;
        }

        favorites.push(result);
        rebuild();
    }

    override function onDisplay() {
        element.html("");
        var div = new Element('<div class="cdb-favorites hide-scroll">').appendTo(element);
        var headerEl = new Element('<div class="header">
            <span class="title">Favorites</span>
        </div>');
        headerEl.appendTo(div);

        var content = new Element('<div class="content"></div>');
        content.appendTo(div);
        for (f in favorites) {
            var resultEl = new Element('<div class="result">
                <span class="entry"><a>${f.text}</a></span>
            </div>');
            resultEl.appendTo(content);
            resultEl.on("click", function(e) {
                f.goto();
            });
        }
	}

    static var _ = hide.ui.View.register(CdbFavorites, {position: Left, width: 400});
}