#!/usr/bin/env bash
#
# generate-app-icon.sh — Composites a random party-themed MeowsDAO cat
# as the CBMPCNative app icon. Run before each build for unique icons.
#
# Usage:  ./generate-app-icon.sh [--dry-run]
#
# Layers are stacked bottom-to-top:
#   Background → Fur → Ears → Nipples → Eyes → Brows → Nose → Collar → Glasses → Headwear → Signature
#
# Party-themed images are preferred where available; other layers pick randomly.
# Previous icons are kept with build-number timestamps in the icon archive dir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAYERS_ROOT="/Users/mark.phillips/Pictures/meowsdao/meowsdao-layers/1_Project_Naked"
ICON_DIR="$PROJECT_DIR/CBMPCNative/Assets.xcassets/AppIcon.appiconset"
ICON_ARCHIVE="$ICON_DIR/archive"
ICON_OUTPUT="$ICON_DIR/AppIcon-1024.png"
ICON_SIZE=1024
LAYER_SIZE=2084
DRY_RUN="${1:-}"

# Layer stacking order (bottom to top)
LAYERS=(Background Fur Ears Nipples Eyes Brows Nose Collar Glasses Headwear Signature)

# Party-themed filename patterns (grep -iE)
PARTY_PATTERNS="party|balloon|confetti|crown|bow|cape|rainbow|flag|blower|propeller|flower|horn|star"

# Layers where we strongly prefer party-themed picks
PARTY_LAYERS="Background Collar Headwear Nose"

pick_random_file() {
    local dir="$1"
    local prefer_party="$2"
    local files=()

    if [[ "$prefer_party" == "yes" ]]; then
        # Collect party-themed files first
        while IFS= read -r f; do
            [[ -n "$f" ]] && files+=("$f")
        done < <(find "$dir" -maxdepth 1 -name '*.png' | grep -iE "$PARTY_PATTERNS" 2>/dev/null || true)
    fi

    # Fall back to all files if no party matches
    if [[ ${#files[@]} -eq 0 ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] && files+=("$f")
        done < <(find "$dir" -maxdepth 1 -name '*.png' -not -name '.*' 2>/dev/null)
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        echo ""
        return
    fi

    # Filter out "No_*" and "No " files (e.g., No_glasses.png, No_hat.png, No_nipples.png)
    local filtered=()
    for f in "${files[@]}"; do
        local base
        base="$(basename "$f")"
        if [[ ! "$base" =~ ^No[_\ ] ]]; then
            filtered+=("$f")
        fi
    done

    # If everything was filtered, use the original set
    if [[ ${#filtered[@]} -eq 0 ]]; then
        filtered=("${files[@]}")
    fi

    local idx=$((RANDOM % ${#filtered[@]}))
    echo "${filtered[$idx]}"
}

# --- Archive previous icon ---
archive_previous() {
    if [[ -f "$ICON_OUTPUT" ]]; then
        mkdir -p "$ICON_ARCHIVE"
        local build_num
        build_num=$(grep -o 'CURRENT_PROJECT_VERSION = [0-9]*' \
            "$PROJECT_DIR/CBMPCNative.xcodeproj/project.pbxproj" 2>/dev/null | head -1 | awk '{print $3}')
        build_num="${build_num:-unknown}"
        local ts
        ts="$(date +%Y%m%d-%H%M%S)"
        local archive_name="AppIcon-build${build_num}-${ts}.png"
        cp "$ICON_OUTPUT" "$ICON_ARCHIVE/$archive_name"
        echo "[icon-gen] Archived previous icon as $archive_name"
    fi
}

# --- Main ---
echo "[icon-gen] Generating party-themed app icon..."
echo "[icon-gen] Layers root: $LAYERS_ROOT"

if [[ ! -d "$LAYERS_ROOT" ]]; then
    echo "[icon-gen] ERROR: Layers directory not found: $LAYERS_ROOT"
    exit 1
fi

# Select one image per layer
declare -a SELECTED
MANIFEST=""
for layer in "${LAYERS[@]}"; do
    layer_dir="$LAYERS_ROOT/$layer"
    if [[ ! -d "$layer_dir" ]]; then
        echo "[icon-gen] SKIP: $layer (directory not found)"
        continue
    fi

    prefer="no"
    for pl in $PARTY_LAYERS; do
        [[ "$layer" == "$pl" ]] && prefer="yes"
    done

    chosen="$(pick_random_file "$layer_dir" "$prefer")"
    if [[ -z "$chosen" ]]; then
        echo "[icon-gen] SKIP: $layer (no PNGs found)"
        continue
    fi

    SELECTED+=("$chosen")
    MANIFEST+="  $layer: $(basename "$chosen")\n"
    echo "[icon-gen]   $layer -> $(basename "$chosen")"
done

if [[ ${#SELECTED[@]} -eq 0 ]]; then
    echo "[icon-gen] ERROR: No layers selected"
    exit 1
fi

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "[icon-gen] DRY RUN — would composite ${#SELECTED[@]} layers"
    exit 0
fi

# Archive the current icon before overwriting
archive_previous

# Composite layers with ImageMagick
# Start with first layer, composite each subsequent layer on top
COMPOSITE_CMD=(magick "${SELECTED[0]}")
for ((i = 1; i < ${#SELECTED[@]}; i++)); do
    COMPOSITE_CMD+=("${SELECTED[$i]}" -composite)
done

# Resize to 1024x1024 for App Store icon
COMPOSITE_CMD+=(-resize "${ICON_SIZE}x${ICON_SIZE}" -background white -flatten -type TrueColor "PNG24:${ICON_OUTPUT}")

"${COMPOSITE_CMD[@]}"

echo "[icon-gen] Output: $ICON_OUTPUT (${ICON_SIZE}x${ICON_SIZE}, no alpha)"

# Write manifest alongside icon for traceability
printf "# Auto-generated app icon manifest\n# $(date -Iseconds)\n$MANIFEST" \
    > "$ICON_DIR/AppIcon-manifest.txt"

echo "[icon-gen] Done."
