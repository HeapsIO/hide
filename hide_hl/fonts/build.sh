if ! command -v bmfont64 >/dev/null 2>&1
then
	echo "bmfont64 not found in PATH"
	exit 1
fi

build() {
	bmfont64 -c "$1.bmfc" -o "../res/font/$1.fnt"
	# need to rename font png without the _0 suffix because heaps expect them that way
	mv "../res/font/${1}_0.png" "../res/font/${1}.png"
}

build Inter-Regular-cv05-cv08-tnum-13pt
build Inter-Regular-cv05-cv08-tnum-26pt
build Inter-Italic-cv05-cv08-tnum-13pt
build Inter-Italic-cv05-cv08-tnum-26pt