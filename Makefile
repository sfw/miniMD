PROJECT = MarkdownQuickLook.xcodeproj
SCHEME = MarkdownQuickLook
DERIVED_DATA = .build/DerivedData
APP = $(DERIVED_DATA)/Build/Products/Release/miniMD.app
DIST = dist
DMG = $(DIST)/miniMD.dmg

.PHONY: build clean dmg show-app show-dmg refresh-quicklook

build:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -derivedDataPath "$(DERIVED_DATA)" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-"

clean:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -derivedDataPath "$(DERIVED_DATA)" clean

dmg: build
	mkdir -p "$(DIST)"
	staging=$$(mktemp -d "/tmp/miniMD-dmg.XXXXXX"); \
	ditto "$(APP)" "$$staging/miniMD.app"; \
	ln -s /Applications "$$staging/Applications"; \
	hdiutil create -volname "miniMD" -srcfolder "$$staging" -ov -format UDZO "$(DMG)"

show-app:
	@printf '%s\n' "$(APP)"

show-dmg:
	@printf '%s\n' "$(DMG)"

refresh-quicklook:
	qlmanage -r
	qlmanage -r cache
