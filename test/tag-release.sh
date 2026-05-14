#!/usr/bin/env bash
set -e

BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# 1. Check for clean working tree (ignoring untracked files)
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${RED}Error: Working directory is not clean.${RESET}"
    echo "Please commit all your changes before running the release process."
    exit 1
fi

# 2. Get current version and calculate next patch version
CURRENT_VERSION=$(grep -oE '\.version = "[0-9]+\.[0-9]+\.[0-9]+"' build.zig.zon | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
NEW_VERSION="${VERSION_PARTS[0]}.${VERSION_PARTS[1]}.$((VERSION_PARTS[2] + 1))"

echo -e "${BOLD}Current version:${RESET} $CURRENT_VERSION"
echo -e "${BOLD}Bumping to:${RESET} $NEW_VERSION"

# 3. Update build.zig.zon
echo -e "\n${BOLD}[1/7] Updating build.zig.zon to $NEW_VERSION...${RESET}"
sed -i.bak -e "s/\.version = \"$CURRENT_VERSION\"/.version = \"$NEW_VERSION\"/" build.zig.zon
rm build.zig.zon.bak

# 4. Format and Test
echo -e "\n${BOLD}[2/7] Formatting code (make fmt)...${RESET}"
make fmt
echo -e "\n${BOLD}[3/7] Running tests (make test)...${RESET}"
make test

# 5. Benchmark (Release verification)
echo -e "\n${BOLD}[4/7] Running release benchmark and verification (make bench)...${RESET}"
make bench

# 6. Verify output logic
if ! git diff --quiet test/output.txt; then
    echo -e "\n${RED}[ERROR] test/output.txt changed during benchmark verification!${RESET}"
    echo -e "${RED}This means the compiled release binary behaves differently than the committed baseline.${RESET}"
    echo -e "${RED}Aborting release and reverting state.${RESET}"
    git restore build.zig.zon test/output.txt benchmarks.log 2>/dev/null || true
    exit 1
fi

# 7. Commit, Tag, and Push
echo -e "\n${BOLD}[5/7] Preparing Annotated Tag...${RESET}"
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LAST_TAG" ]; then
    CHANGES=$(git log ${LAST_TAG}..HEAD --oneline --no-decorate | sed 's/^/- /')
else
    CHANGES=$(git log --oneline --no-decorate | sed 's/^/- /')
fi

echo -e "${BOLD}Changes since $LAST_TAG:${RESET}"
echo "$CHANGES"
echo ""

echo -e "\n${BOLD}[6/7] Committing version bump...${RESET}"
git commit -am "chore: release v$NEW_VERSION"

echo -e "\n${BOLD}[7/7] Tagging and Pushing...${RESET}"
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION" -m "Changes:" -m "$CHANGES"
git push origin master --follow-tags

echo -e "\n${GREEN}Successfully released and deployed v$NEW_VERSION!${RESET}"
