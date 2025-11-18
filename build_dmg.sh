#!/bin/bash
# Creates a distributable DMG with a customized layout for macOS application distribution
#
# Usage:
#   ./dmg.sh [VERSION]
#   SKIP_BUILD=true ./dmg.sh 1.0.0
#   BUILD_OUTPUT_DIR=/path/to/app ./dmg.sh

set -e
set -o pipefail

# Configuration
readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_NAME="Rabbit Converter"
readonly BUILD_DIR="${PROJECT_DIR}/dmg-build"
readonly RELEASE_DIR="${PROJECT_DIR}/release"

# DMG appearance settings
readonly DMG_WINDOW_WIDTH=500
readonly DMG_WINDOW_HEIGHT=300
readonly DMG_ICON_SIZE=72
readonly DMG_APP_ICON_X=120
readonly DMG_APP_ICON_Y=150
readonly DMG_APPLICATIONS_ICON_X=380
readonly DMG_APPLICATIONS_ICON_Y=150

# Output helpers for user-friendly messages
print_info() { echo "[INFO] $*"; }
print_success() { echo "[SUCCESS] $*"; }
print_error() { echo "[ERROR] $*" >&2; }
print_warning() { echo "[WARNING] $*"; }
print_step() { echo ""; echo "==> $*"; }
print_detail() { echo "    $*"; }

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        print_error "Something went wrong during DMG creation"
        print_info "The script encountered an error and will now clean up"
        if [ -d "$MOUNT_DIR" ] && mount | grep -q "$MOUNT_DIR"; then
            print_info "Unmounting any mounted disk images..."
            hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
        fi
        echo ""
        print_info "If the problem persists, try:"
        print_detail "1. Run with SKIP_BUILD=true if the app is already built"
        print_detail "2. Check that Xcode is properly configured"
        print_detail "3. Ensure you have write permissions in this directory"
        echo ""
    fi
    return $exit_code
}

trap cleanup EXIT

# Determine version
get_version() {
    if [ -n "$1" ]; then
        print_info "Using version from command line: $1" >&2
        echo "$1"
    else
        print_info "Extracting version from Xcode project..." >&2
        local version
        version=$(grep -A 1 "MARKETING_VERSION" "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj" | \
                  grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?" | head -n 1)
        
        if [ -z "$version" ]; then
            echo "" >&2
            print_error "Could not automatically determine the version number"
            print_info "The MARKETING_VERSION is not set in your Xcode project" >&2
            echo "" >&2
            print_info "You can fix this by either:" >&2
            print_detail "1. Providing version as argument: $0 1.0.0" >&2
            print_detail "2. Setting MARKETING_VERSION in Xcode project settings" >&2
            echo "" >&2
            exit 1
        fi
        print_success "Detected version: $version" >&2
        echo "$version"
    fi
}

# Find built application
find_app() {
    print_info "Searching for built application..." >&2
    
    if [ -n "$BUILD_OUTPUT_DIR" ] && [ -d "$BUILD_OUTPUT_DIR" ]; then
        print_detail "Checking custom location: $BUILD_OUTPUT_DIR" >&2
        if [ -d "$BUILD_OUTPUT_DIR/${PROJECT_NAME}.app" ]; then
            print_success "Found application in custom location" >&2
            print_detail "$BUILD_OUTPUT_DIR/${PROJECT_NAME}.app" >&2
            echo "$BUILD_OUTPUT_DIR/${PROJECT_NAME}.app"
            return 0
        else
            echo "" >&2
            print_error "Application not found at specified location"
            print_detail "Expected: $BUILD_OUTPUT_DIR/${PROJECT_NAME}.app" >&2
            echo "" >&2
            return 1
        fi
    fi
    
    local derived_data_name
    derived_data_name=$(echo "${PROJECT_NAME}" | tr ' ' '_')
    
    # First check local DerivedData (used by this script's build)
    print_detail "Checking local DerivedData..." >&2
    local app_path="${PROJECT_DIR}/DerivedData/Build/Products/Release/${PROJECT_NAME}.app"
    
    if [ ! -d "$app_path" ]; then
        print_detail "Local Release build not found, trying Debug..." >&2
        app_path="${PROJECT_DIR}/DerivedData/Build/Products/Debug/${PROJECT_NAME}.app"
    fi
    
    # If not found locally, search in Xcode's default DerivedData
    if [ ! -d "$app_path" ]; then
        print_detail "Searching in Xcode DerivedData..." >&2
        # Try Release configuration first, then Debug as fallback
        app_path=$(find ~/Library/Developer/Xcode/DerivedData/${derived_data_name}-*/Build/Products/Release \
                        -name "${PROJECT_NAME}.app" -type d 2>/dev/null | head -n 1)

        if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
            print_detail "Release build not found, trying Debug configuration..." >&2
            app_path=$(find ~/Library/Developer/Xcode/DerivedData/${derived_data_name}-*/Build/Products/Debug \
                            -name "${PROJECT_NAME}.app" -type d 2>/dev/null | head -n 1)
        fi
    fi
    
    if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
        echo "" >&2
        print_error "Could not locate the built application"
        print_info "This usually means the app hasn't been built yet" >&2
        echo "" >&2
        print_info "Searched locations:" >&2
        print_detail "${PROJECT_DIR}/DerivedData/Build/Products/Release" >&2
        print_detail "${PROJECT_DIR}/DerivedData/Build/Products/Debug" >&2
        print_detail "~/Library/Developer/Xcode/DerivedData/${derived_data_name}-*/Build/Products/Release" >&2
        print_detail "~/Library/Developer/Xcode/DerivedData/${derived_data_name}-*/Build/Products/Debug" >&2
        [ -n "$BUILD_OUTPUT_DIR" ] && print_detail "$BUILD_OUTPUT_DIR" >&2
        echo "" >&2
        print_info "To fix this:" >&2
        print_detail "1. Build the app in Xcode first (Product > Build)" >&2
        print_detail "2. Or let this script build it (remove SKIP_BUILD=true)" >&2
        print_detail "3. Or specify BUILD_OUTPUT_DIR=/path/to/app" >&2
        echo "" >&2
        return 1
    fi
    
    print_success "Found application in DerivedData" >&2
    print_detail "$app_path" >&2
    echo "$app_path"
}

# Build the application
build_app() {
    if [ "$SKIP_BUILD" = "true" ]; then
        print_warning "Skipping build step (SKIP_BUILD=true)"
        print_detail "Will use existing built application"
        return 0
    fi
    
    print_step "Building ${PROJECT_NAME} for release"
    print_info "This may take a few minutes..."
    print_detail "Configuration: Release"
    print_detail "Code signing: Disabled (for DMG distribution)"
    
    if xcodebuild -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
               -scheme "${PROJECT_NAME}" \
               -configuration Release \
               -derivedDataPath "${PROJECT_DIR}/DerivedData" \
               clean build \
               CODE_SIGN_IDENTITY="" \
               CODE_SIGNING_REQUIRED=NO \
               CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"; then
        print_success "Build completed successfully"
    else
        echo ""
        print_error "Build failed"
        print_info "Check the output above for details"
        echo ""
        exit 1
    fi
}

# Prepare DMG staging directory
prepare_staging() {
    local app_path="$1"
    
    print_step "Preparing DMG contents"
    
    if [ -d "$BUILD_DIR" ]; then
        print_info "Cleaning previous staging area..."
        rm -rf "$BUILD_DIR"
    fi
    
    if [ -d "$RELEASE_DIR" ]; then
        print_info "Cleaning previous release directory..."
        rm -rf "$RELEASE_DIR"
    fi
    
    print_info "Creating staging directories..."
    mkdir -p "$BUILD_DIR"
    mkdir -p "$RELEASE_DIR"
    
    print_info "Copying application bundle to staging area..."
    print_detail "Source: $app_path"
    print_detail "Destination: $BUILD_DIR/"
    
    if ! cp -R "$app_path" "$BUILD_DIR/"; then
        echo ""
        print_error "Failed to copy application bundle"
        print_detail "Source: $app_path"
        print_detail "Destination: $BUILD_DIR/"
        echo ""
        exit 1
    fi
    
    print_info "Creating Applications folder shortcut..."
    print_detail "This allows users to drag-and-drop to install"
    ln -s /Applications "$BUILD_DIR/Applications"
    
    print_success "Staging area ready"
}

# Create and customize DMG
create_dmg() {
    local dmg_name="$1"
    local temp_dmg="${RELEASE_DIR}/${dmg_name}-temp.dmg"
    local final_dmg="${RELEASE_DIR}/${dmg_name}.dmg"
    local mount_dir="/Volumes/${PROJECT_NAME}"
    
    print_step "Creating disk image" >&2
    
    if [ -f "$final_dmg" ]; then
        print_warning "Removing existing DMG with same name..." >&2
        rm "$final_dmg"
    fi
    
    print_info "Creating temporary writable DMG..." >&2
    print_detail "This will contain your app and the Applications shortcut" >&2
    hdiutil create -volname "${PROJECT_NAME}" \
                   -srcfolder "$BUILD_DIR" \
                   -ov \
                   -format UDRW \
                   "$temp_dmg" >/dev/null
    
    print_info "Mounting DMG for customization..." >&2
    hdiutil attach "$temp_dmg" -mountpoint "$mount_dir" -nobrowse >/dev/null
    sleep 2
    
    print_info "Customizing DMG window appearance..." >&2
    print_detail "Setting icon positions and window size" >&2
    print_detail "Window size: ${DMG_WINDOW_WIDTH}x${DMG_WINDOW_HEIGHT}" >&2
    print_detail "Icon size: ${DMG_ICON_SIZE}px" >&2
    
    if osascript <<EOF >/dev/null 2>&1
tell application "Finder"
    tell disk "${PROJECT_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, $((100 + DMG_WINDOW_WIDTH)), $((100 + DMG_WINDOW_HEIGHT))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to ${DMG_ICON_SIZE}
        set position of item "${PROJECT_NAME}.app" of container window to {${DMG_APP_ICON_X}, ${DMG_APP_ICON_Y}}
        set position of item "Applications" of container window to {${DMG_APPLICATIONS_ICON_X}, ${DMG_APPLICATIONS_ICON_Y}}
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
    then
        print_success "DMG appearance customized" >&2
    else
        print_warning "Could not fully customize DMG appearance (non-critical)" >&2
    fi
    
    sync
    
    print_info "Unmounting temporary DMG..." >&2
    hdiutil detach "$mount_dir" >/dev/null
    
    print_info "Compressing to final read-only DMG..." >&2
    print_detail "Using maximum compression (this may take a moment)" >&2
    hdiutil convert "$temp_dmg" \
                    -format UDZO \
                    -imagekey zlib-level=9 \
                    -o "$final_dmg" >/dev/null
    
    print_info "Removing temporary files..." >&2
    rm "$temp_dmg"
    
    print_success "DMG creation complete" >&2
    echo "$final_dmg"
}

# Main execution
main() {
    echo ""
    echo "========================================"
    echo "  Rabbit Converter DMG Builder"
    echo "========================================"
    echo ""
    
    local version
    version=$(get_version "$1")
    
    local dmg_name="${PROJECT_NAME}-${version}"
    
    echo ""
    print_info "Configuration:"
    print_detail "Project: ${PROJECT_NAME}"
    print_detail "Version: ${version}"
    print_detail "Output: ${dmg_name}.dmg"
    echo ""
    
    build_app
    
    print_step "Locating built application"
    local app_path
    app_path=$(find_app)
    print_detail "Path: $app_path"
    
    prepare_staging "$app_path"
    
    local final_dmg
    final_dmg=$(create_dmg "$dmg_name")
    
    print_step "Cleaning up temporary files"
    print_info "Removing staging directory..."
    rm -rf "$BUILD_DIR"
    print_success "Cleanup complete"
    
    local dmg_size
    dmg_size=$(du -h "$final_dmg" | cut -f1)
    
    echo ""
    echo "========================================"
    print_success "DMG CREATED SUCCESSFULLY!"
    echo "========================================"
    echo ""
    print_info "Your installer is ready:"
    print_detail "Location: $final_dmg"
    print_detail "Size: $dmg_size"
    echo ""
    print_info "Next steps:"
    echo ""
    echo "  To test the installer:"
    print_detail "open '$final_dmg'"
    echo ""
    echo "  To distribute to users:"
    print_detail "1. Upload the DMG to your website or cloud storage"
    print_detail "2. Share the download link with users"
    print_detail "3. Users will download, mount, and drag to Applications"
    echo ""
    echo "  Installation instructions for users:"
    print_detail "1. Double-click the downloaded DMG file"
    print_detail "2. Drag '${PROJECT_NAME}.app' to the Applications folder"
    print_detail "3. Eject the disk image"
    print_detail "4. Launch ${PROJECT_NAME} from Applications"
    echo ""
    print_success "All done! Your DMG is ready to distribute."
    echo ""
}

main "$@"
