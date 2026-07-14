APP_NAME := clipboard manager
DMG_NAME := Clipboard Manager.dmg
XCODEPROJ := $(APP_NAME).xcodeproj
SCHEME := $(APP_NAME)

.PHONY: build build-release dmg release push gh-release tag clean

build:
	xcodebuild -project "$(XCODEPROJ)" -scheme "$(SCHEME)" build

build-release:
	xcodebuild -project "$(XCODEPROJ)" -scheme "$(SCHEME)" -configuration Release -derivedDataPath build/DerivedData build

dmg: build-release
	@echo "--- Packaging DMG ---"
	rm -rf build/temp_dmg "$(DMG_NAME)"
	mkdir -p build/temp_dmg
	cp -R "build/DerivedData/Build/Products/Release/$(APP_NAME).app" build/temp_dmg/
	ln -s /Applications build/temp_dmg/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder build/temp_dmg -ov -format UDZO "$(DMG_NAME)"
	rm -rf build/temp_dmg
	@echo "Created: $(DMG_NAME)"

push:
	git push origin main --tags

tag:
	@read -p "Version (e.g. v1.1.0): " v; git tag $$v

gh-release:
	@read -p "Version (e.g. v1.1.0): " v; \
	read -p "Title: " t; \
	gh release create $$v "./$(DMG_NAME)" --title "$$t"

release: dmg
	@read -p "Version (e.g. v1.1.0): " v; \
	read -p "Release title: " t; \
	git tag $$v && git push origin main --tags; \
	gh release create $$v "./$(DMG_NAME)" --title "$$t"

clean:
	rm -rf build "$(DMG_NAME)"