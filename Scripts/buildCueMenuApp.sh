#!/bin/bash
echo "Build CueMenuApp"

# Variables
PROJECT_PATH="/Users/nick/Library/Mobile Documents/com~apple~CloudDocs/Active/Cue/Cue.xcodeproj" # Update with the actual path to your project
SCHEME="CueMenuApp"                        # Scheme name for the app
CONFIGURATION="Release"                     # Build configuration
BUILD_DIR="./BuildOutput"                   # Output directory for the build
DERIVED_DATA_PATH="./DerivedData"           # Optional: custom derived data location

# Function to print status messages
print_status() {
	echo -e "\n==== $1 ====\n"
}

# Start the build process
print_status "Cleaning previous builds"
rm -rf "$BUILD_DIR"
rm -rf "$DERIVED_DATA_PATH"
mkdir -p "$BUILD_DIR"

print_status() "Cleaning Build"

xcodebuild clean -project "$PROJECT_PATH" -scheme "CueMenuApp"
rm -rf ./DerivedData ./BuildOutput

print_status "Building $SCHEME for Release configuration"
xcodebuild -project "$PROJECT_PATH" \
		   -scheme "$SCHEME" \
		   -configuration "$CONFIGURATION" \
		   -derivedDataPath "$DERIVED_DATA_PATH" \
		   -archivePath "$BUILD_DIR/$SCHEME.xcarchive" \
		   archive | tee "$BUILD_DIR/build.log"

# Verify if the build succeeded
APP_PATH="$BUILD_DIR/$SCHEME.xcarchive/Products/Applications/$SCHEME.app"
if [ -d "$APP_PATH" ]; then
	print_status "Build succeeded! App is located at: $APP_PATH"
else
	print_status "Build failed. Check the logs at: $BUILD_DIR/build.log"
	exit 1
fi
