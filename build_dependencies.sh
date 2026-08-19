#!/usr/bin/env bash

PROJ_ROOT=$(pwd)

# scons is needed for cpp extensions
# pyenv is used for local dev; CI runners provide python directly
if command -v pyenv >/dev/null 2>&1; then
	pyenv local 3.13
fi
pip install pipx scons --quiet
TARGET="${target:-x86_64-unknown-linux-gnu}"
	
build_ayagami () {
	echo -e "\n#### Preparing ayagami-gd\n\n"

	WORKDIR=$PROJ_ROOT/thirdparty/ayagami
	ADDONDIR=$PROJ_ROOT/addons

	mkdir -p $ADDONDIR
	
	cd $WORKDIR
	
	make package target=$TARGET
	cp -r $WORKDIR/addons/ayagami $ADDONDIR

	cp $WORKDIR/LICENSE $PROJ_ROOT/license/LICENSE.ayagami.md
	cp $WORKDIR/README.md $ADDONDIR/ayagami/README.md
	
	echo "*" > $ADDONDIR/ayagami/.gitignore
	
	# log completion
	find $ADDONDIR/ayagami -type f

	cd $PROJ_ROOT
}

build_virtualcamera () {
	echo -e "\n#### Preparing gd-virtualcamera\n\n"

	WORKDIR=$PROJ_ROOT/thirdparty/gd-virtualcamera
	ADDONDIR=$PROJ_ROOT/addons

	mkdir -p $ADDONDIR
	
	cd $WORKDIR
	
	make package
	cp -r $WORKDIR/addons/virtualcamera $ADDONDIR

	cp LICENSE.md $PROJ_ROOT/license/LICENSE.gdvirtualcamera.md
	cp README.md $ADDONDIR/virtualcamera/README.md
	echo "*" > $ADDONDIR/virtualcamera/.gitignore
	
	# log completion
	find $ADDONDIR/virtualcamera -type f

	cd $PROJ_ROOT
}

build_global_input() {
	echo -e "\n#### Preparing gd-global-input\n\n"

	WORKDIR=$PROJ_ROOT/native/gd-global-input
	ADDONDIR=$PROJ_ROOT/addons

	mkdir -p $ADDONDIR

	cd $WORKDIR

	make package
	cp -r $WORKDIR/addons/global_input $ADDONDIR

	cp LICENSE $PROJ_ROOT/license/LICENSE.globalinput.md
	echo "*" > $ADDONDIR/global_input/.gitignore

	# log completion
	find $ADDONDIR/global_input -type f

	cd $PROJ_ROOT
}

build_vrm () {
    cp -r $PROJ_ROOT/thirdparty/godot-vrm/addons $PROJ_ROOT
	cp $PROJ_ROOT/thirdparty/godot-vrm/LICENSE $PROJ_ROOT/license/LICENSE.godotvrm.md
	echo "*" > $ADDONDIR/vrm/.gitignore
	echo "*" > $ADDONDIR/Godot-MToon-Shader/.gitignore
}

# fetch submodules if they haven't been already
git submodule update --init --recursive

build_ayagami
build_vrm
build_virtualcamera
build_global_input
