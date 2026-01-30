#!/bin/bash
# Separate DMG Builder for macOS Applications
# Builds separate ARM64 and Intel DMGs for optimal size
#
# Usage:
#   ./build-dmg.sh [VERSION]
#
# Environment Variables:
#   VERSION         - Override version (default: auto-detect from Xcode)
#   ARCH            - Build specific arch: "arm64", "x86_64", or "both" (default: both)
#   APP_NAME        - Application name (default: Rabbit Converter)

set -e
set -o pipefail

#==============================================================================
# CONFIGURATION
#==============================================================================

APP_NAME="${APP_NAME:-Rabbit Converter}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_DIR="${PROJECT_DIR}/Build"
BUILD_DIR="${PROJECT_DIR}/dmg-temp"
OUTPUT_DIR="${PROJECT_DIR}/release"
ARCH="${ARCH:-both}"

# DMG Configuration
DMG_WINDOW_WIDTH=600
DMG_WINDOW_HEIGHT=400
DMG_ICON_SIZE=80
DMG_TEXT_SIZE=12

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log_section() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $*"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[✓] $*"
}

die() {
    log_error "$*"
    exit 1
}

cleanup() {
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
}

trap cleanup EXIT

#==============================================================================
# VERSION DETECTION
#==============================================================================

get_version() {
    if [ -n "$1" ]; then
        echo "$1"
        return
    fi
    
    if [ -n "$VERSION" ]; then
        echo "$VERSION"
        return
    fi
    
    local project_file="${PROJECT_DIR}/${APP_NAME}.xcodeproj/project.pbxproj"
    
    if [ ! -f "$project_file" ]; then
        die "Cannot find Xcode project at: $project_file"
    fi
    
    local version=$(grep -m 1 "MARKETING_VERSION" "$project_file" | \
                    sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);/\1/p' | \
                    tr -d ' ')
    
    if [ -z "$version" ]; then
        die "Could not detect version. Set it in Xcode or pass as argument: $0 1.0.0"
    fi
    
    echo "$version"
}

#==============================================================================
# BUILD FOR SPECIFIC ARCHITECTURE
#==============================================================================

build_for_arch() {
    local arch="$1"
    local arch_name="$2"
    
    log_section "Building for $arch_name ($arch)" >&2
    
    local project="${PROJECT_DIR}/${APP_NAME}.xcodeproj"
    local output_dir="${DERIVED_DATA_DIR}/${arch}"
    
    if [ ! -d "$project" ]; then
        die "Xcode project not found: $project"
    fi
    
    mkdir -p "$output_dir"
    
    log "Compiling $arch_name binary..." >&2
    xcodebuild clean build \
        -project "$project" \
        -scheme "$APP_NAME" \
        -configuration Release \
        -arch "$arch" \
        -derivedDataPath "$DERIVED_DATA_DIR" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        CONFIGURATION_BUILD_DIR="$output_dir" \
        > "${DERIVED_DATA_DIR}/build-${arch}.log" 2>&1 || die "$arch_name build failed. Check ${DERIVED_DATA_DIR}/build-${arch}.log"
    
    local app_path="${output_dir}/${APP_NAME}.app"
    
    if [ ! -d "$app_path" ]; then
        die "Built app not found at: $app_path"
    fi
    
    # Get binary size
    local binary_name=$(basename "$app_path" .app)
    local binary_path="${app_path}/Contents/MacOS/${binary_name}"
    local binary_size=$(du -h "$binary_path" | cut -f1)
    
    log_success "$arch_name build complete (binary: $binary_size)" >&2
    
    printf '%s' "$app_path"
}

#==============================================================================
# CREATE DMG FOR ARCHITECTURE
#==============================================================================

create_dmg_for_arch() {
    local version="$1"
    local app_path="$2"
    local arch="$3"
    local arch_label="$4"
    
    log_section "Creating DMG for $arch_label" >&2
    
    local dmg_name="${APP_NAME}-${version}-${arch_label}"
    local temp_dmg="${OUTPUT_DIR}/${dmg_name}-temp.dmg"
    local final_dmg="${OUTPUT_DIR}/${dmg_name}.dmg"
    
    # Prepare staging directory
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    # Copy app to staging area
    log "Preparing DMG contents..." >&2
    cp -R "$app_path" "$BUILD_DIR/" || die "Failed to copy application"
    
    # Create Applications symlink
    ln -s /Applications "$BUILD_DIR/Applications"
    
    # Remove any existing DMG
    [ -f "$final_dmg" ] && rm "$final_dmg"
    [ -f "$temp_dmg" ] && rm "$temp_dmg"
    
    # Create temporary DMG
    log "Creating disk image..." >&2
    hdiutil create -volname "$APP_NAME" \
                   -srcfolder "$BUILD_DIR" \
                   -ov -format UDRW \
                   "$temp_dmg" > /dev/null
    
    # Mount for customization
    log "Customizing appearance..." >&2
    local mount_point="/Volumes/$APP_NAME"
    
    # Unmount if already mounted
    if [ -d "$mount_point" ]; then
        hdiutil detach "$mount_point" 2>/dev/null || true
        sleep 1
    fi
    
    local device=$(hdiutil attach -readwrite -noverify -noautoopen "$temp_dmg" | \
                   grep -E "^/dev/" | head -n 1 | awk '{print $1}')
    
    sleep 2
    
    # Customize with AppleScript
    /usr/bin/osascript <<-EOD > /dev/null 2>&1
        tell application "Finder"
            tell disk "$APP_NAME"
                open
                set current view of container window to icon view
                set toolbar visible of container window to false
                set statusbar visible of container window to false
                set the bounds of container window to {100, 100, 700, 500}
                set viewOptions to the icon view options of container window
                set arrangement of viewOptions to not arranged
                set icon size of viewOptions to $DMG_ICON_SIZE
                set text size of viewOptions to $DMG_TEXT_SIZE
                set position of item "${APP_NAME}.app" of container window to {150, 200}
                set position of item "Applications" of container window to {450, 200}
                close
                open
                update without registering applications
                delay 2
            end tell
        end tell
EOD
    
    sleep 2
    sync
    
    # Unmount using device
    log "Finalizing..." >&2
    hdiutil detach "$device" -force > /dev/null 2>&1 || {
        sleep 2
        hdiutil detach "$device" -force > /dev/null 2>&1 || true
    }
    
    sleep 2
    
    # Convert to compressed read-only
    hdiutil convert "$temp_dmg" \
                    -format UDZO \
                    -imagekey zlib-level=9 \
                    -o "$final_dmg" > /dev/null
    
    # Clean up temp DMG
    rm "$temp_dmg"
    
    # Get final size
    local dmg_size=$(du -h "$final_dmg" | cut -f1)
    
    log_success "DMG created: $(basename "$final_dmg") ($dmg_size)" >&2
    
    printf '%s' "$final_dmg"
}

#==============================================================================
# MAIN
#==============================================================================

main() {
    log_section "DMG Builder for $APP_NAME"
    
    # Get version
    local version=$(get_version "$1")
    log "Version: $version"
    
    # Clean previous builds
    if [ -d "$DERIVED_DATA_DIR" ]; then
        log "Cleaning previous build data..."
        rm -rf "$DERIVED_DATA_DIR"
    fi
    
    mkdir -p "$OUTPUT_DIR"
    
    local dmg_files=()
    
    # Build and create DMG for ARM64
    if [ "$ARCH" = "both" ] || [ "$ARCH" = "arm64" ]; then
        local arm_app=$(build_for_arch "arm64" "Apple Silicon")
        local arm_dmg=$(create_dmg_for_arch "$version" "$arm_app" "arm64" "AppleSilicon")
        dmg_files+=("$arm_dmg")
    fi
    
    # Build and create DMG for Intel
    if [ "$ARCH" = "both" ] || [ "$ARCH" = "x86_64" ]; then
        local intel_app=$(build_for_arch "x86_64" "Intel")
        local intel_dmg=$(create_dmg_for_arch "$version" "$intel_app" "x86_64" "Intel")
        dmg_files+=("$intel_dmg")
    fi
    
    log_section "Build Complete!"
    
    echo "DMG installers created:"
    echo ""
    for dmg in "${dmg_files[@]}"; do
        local size=$(du -h "$dmg" | cut -f1)
        echo "  • $(basename "$dmg") ($size)"
    done
    echo ""
    echo "Distribution:"
    echo "  • AppleSilicon.dmg → For M1, M2, M3, M4 Macs (ARM64)"
    echo "  • Intel.dmg        → For Intel-based Macs (x86_64)"
    echo ""
    echo "Users should download the version matching their Mac's processor."
    echo ""
    log_success "All done!"
}

main "$@"
