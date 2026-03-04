#!/bin/bash
# Copy FunnyHow module to app bundle

# Source and destination paths
SOURCE_DIR="${PROJECT_DIR}/extensions/funnyhow"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/extensions/hs/funnyhow"

echo "Copying FunnyHow module..."
echo "From: ${SOURCE_DIR}"
echo "To: ${DEST_DIR}"

# Create destination directory
mkdir -p "${DEST_DIR}"

# Copy module files
cp -R "${SOURCE_DIR}/"* "${DEST_DIR}/"

echo "✅ FunnyHow module copied successfully"
