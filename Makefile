VERSION = 1.0.0
INSTALL_DIR = $(HOME)/Library/Application Support/Nextpad++/plugins/AdminSave
# macOS 11 is the oldest system Nextpad++ itself runs on.
CXX = clang++ -std=c++17 -fobjc-arc -Wall -Wextra -mmacosx-version-min=11.0 -framework Foundation

# Universal, like the app itself.
AdminSave.dylib: AdminSave.mm NppPluginInterfaceMac.h Makefile
	$(CXX) -arch arm64 -arch x86_64 -dynamiclib -DADMINSAVE_VERSION='"$(VERSION)"' \
		-framework AppKit -framework Security -o $@ AdminSave.mm

adminsave-test: test.mm NppPluginInterfaceMac.h Makefile
	$(CXX) -o $@ test.mm

test: AdminSave.dylib adminsave-test
	./adminsave-test ./AdminSave.dylib

# Shows the admin prompt three times (Touch ID when enabled for sudo, else the password).
test-auth: AdminSave.dylib adminsave-test
	./adminsave-test ./AdminSave.dylib --auth

# Quit Nextpad++ first. rm before cp: overwriting a signed dylib in place breaks its signature check.
install: AdminSave.dylib
	mkdir -p "$(INSTALL_DIR)" && rm -f "$(INSTALL_DIR)/AdminSave.dylib" && cp AdminSave.dylib "$(INSTALL_DIR)/"

# Release archive in the layout Plugins Admin expects: AdminSave/AdminSave.dylib.
zip: AdminSave.dylib
	rm -rf dist && mkdir -p dist/AdminSave && cp AdminSave.dylib dist/AdminSave/
	cd dist && zip -qr AdminSavev$(VERSION).zip AdminSave

.PHONY: test test-auth install zip
