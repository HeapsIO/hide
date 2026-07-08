# path to the msdfgen executable to generate the icons
MSDFGEN := $(SHIRO_TOOLS)/tools/msdfgen.exe


# pxrange 8 : need to satisfy min_render_size / texture_size * pxrange >= 2
#			  our min_render_size should be around 16px, so pxrange need to be at least 8
MSDFGEN_FLAGS := --pxrange 8 -scale 2 -size 64 64

OUTPUT := ../res/ui/icons/

SRC := $(wildcard **/*.svg)
PNG := $(patsubst src/%.svg, $(OUTPUT)%.sdf.png, $(SRC))

$(OUTPUT)%.sdf.png : %.svg
	$(MSDFGEN) -svg $< -o $@ $(MSDFGEN_FLAGS)

.PHONY: all
all: $(PNG)