#!/usr/bin/env bash
set -euo pipefail

# ======================================================================
# Kairos Bootstrap (polyrepo, fully non-interactive)
# - Generates local scaffolds (CDK, Next.js, Spring Boot, Fastify)
# - Creates GitHub repos via HTTPS and pushes initial commits
# - Creates krs-root repo, adds submodules, generates VS Code workspace
# - Reads GitHub user from .env (GITHUB_USER or OWNER), supports VISIBILITY
# ======================================================================

ROOT_DIR="$(pwd)"
BUILD_DIR="$ROOT_DIR/.bootstrap_build"

# ---------- .env 読み込み（任意） ----------
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

# ---------- 変数（.env優先） ----------
GITHUB_USER="${GITHUB_USER:-${OWNER:-katsuki-ito-10}}"
VISIBILITY="${VISIBILITY:-public}"   # public | private | internal(org)

echo "Using GitHub user: ${GITHUB_USER} (visibility: ${VISIBILITY})"

# ---------- ユーティリティ ----------
sanitize_pkg() {
  # e.g. 'krs-identity-gw' -> 'krsidentitygw'
  echo "$1" | tr -d '-' | tr '[:upper:]' '[:lower:]'
}

ensure_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required"; exit 1; }; }

# 必須ツール（gh, git, unzip は強制 / cdk, npx, spring は警告）
ensure_cmd gh
ensure_cmd git
ensure_cmd unzip

command -v cdk    >/dev/null 2>&1 || echo "WARN: cdk not found (krs-infra will be a placeholder)"
command -v npx    >/dev/null 2>&1 || echo "WARN: npx not found (krs-frontend may fail)"
command -v spring >/dev/null 2>&1 || echo "WARN: spring CLI not found (will fallback to curl for Spring Boot)"
command -v jq     >/dev/null 2>&1 || true

# ---------- レイアウト準備 ----------
echo "=== [1/5] Prepare working layout ==="
rm -rf "$BUILD_DIR" krs-root
mkdir -p "$BUILD_DIR"

echo "=== [2/5] Generate service scaffolds locally (in $BUILD_DIR) ==="

# 2.1 CDK (TypeScript)
echo "-> Scaffolding: krs-infra (CDK TypeScript)"
mkdir -p "$BUILD_DIR/krs-infra"
(
  cd "$BUILD_DIR/krs-infra"
  if command -v cdk >/dev/null 2>&1; then
    cdk init app --language typescript
    npm install
  else
    cat > README.md <<'MD'
# krs-infra (placeholder)
AWS CDK が未インストールのため、プレースホルダを生成しました。
MD
  fi
)

# 2.2 Next.js (TypeScript) - non-interactive
echo "-> Scaffolding: krs-frontend (Next.js TypeScript)"
(
  cd "$BUILD_DIR"
  if command -v npx >/dev/null 2>&1; then
    npx create-next-app@latest krs-frontend \
      --typescript --eslint --app --src-dir \
      --import-alias "@/*" --no-tailwind --yes
  else
    mkdir -p krs-frontend
    echo "# krs-frontend (placeholder)" > krs-frontend/README.md
  fi
)

# 2.3 Spring Boot (Gradle) - prefer spring CLI ZIP, fallback to curl
spring_services=(
  "krs-identity-gw"
  "krs-user-profile-svc"
  "krs-session-scheduling-svc"
  "krs-wallet-ledger-svc"
  "krs-notification-svc"
)

for svc in "${spring_services[@]}"; do
  echo "-> Scaffolding: ${svc} (Spring Boot Gradle as ZIP)"
  final_dir="${BUILD_DIR}/${svc}"
  tmp_zip="${BUILD_DIR}/${svc}.zip"
  mkdir -p "${final_dir}"
  rm -f "${tmp_zip}"

  short_pkg="$(sanitize_pkg "${svc}")"
  pkg="dev.kairos.${short_pkg}"

  if command -v spring >/dev/null 2>&1; then
    # Spring CLI で ZIP を生成（出力に存在しないパスを渡すと ZIP を作る挙動）
    spring init \
      --dependencies=web,security,data-jpa \
      --type=gradle-project \
      --java-version=21 \
      --name="${svc}" \
      --package-name="${pkg}" \
      "${tmp_zip}" || true
  fi

  if [[ ! -s "${tmp_zip}" ]]; then
    # Fallback: curl で ZIP を取得（URLエンコード付き）
    curl -sSL -G "https://start.spring.io/starter.zip" \
      --data-urlencode "type=gradle-project" \
      --data-urlencode "language=java" \
      --data-urlencode "javaVersion=21" \
      --data-urlencode "packaging=jar" \
      --data-urlencode "name=${svc}" \
      --data-urlencode "packageName=${pkg}" \
      --data-urlencode "dependencies=web,security,data-jpa" \
      -o "${tmp_zip}"
  fi

  # Zip妥当性チェック（シグネチャ先頭 'PK' を確認）
  if [[ ! -s "${tmp_zip}" ]] || ! head -c 2 "${tmp_zip}" | grep -q "PK"; then
    echo "ERROR: Failed to obtain valid ZIP for ${svc} (got: $(wc -c < "${tmp_zip}" 2>/dev/null || echo 0) bytes)"
    echo "Hint: ネットワークや start.spring.io の応答を確認してください。"
    exit 1
  fi

  unzip -q "${tmp_zip}" -d "${final_dir}"
  rm -f "${tmp_zip}"
done

# 2.4 Fastify (TypeScript)
fastify_services=(
  "krs-messaging-svc"
  "krs-matching-search-svc"
)
for svc in "${fastify_services[@]}"; do
  echo "-> Scaffolding: ${svc} (Fastify + TS)"
  svc_dir="${BUILD_DIR}/${svc}"
  mkdir -p "${svc_dir}"
  (
    cd "${svc_dir}"
    npm init -y >/dev/null 2>&1 || true
    npm install fastify >/dev/null 2>&1 || true
    npm install -D typescript ts-node @types/node nodemon >/dev/null 2>&1 || true
    npx tsc --init --rootDir src --outDir dist --esModuleInterop --resolveJsonModule --module commonjs --target es2020 >/dev/null 2>&1 || true
    mkdir -p src
    cat > src/index.ts <<'TS'
import Fastify from "fastify";
const app = Fastify();
app.get("/", async () => ({ status: "ok" }));
app.listen({ port: 3000, host: "0.0.0.0" }).then(() => {
  console.log("Service running on http://localhost:3000");
});
TS
    cat > .gitignore <<'GI'
node_modules
dist
.env
npm-debug.log*
yarn.lock
pnpm-lock.yaml
GI
  )
done

echo "=== [3/5] Create/push GitHub repos for each service (HTTPS) ==="
for dir in $(ls "$BUILD_DIR"); do
  repo_dir="$BUILD_DIR/$dir"
  (
    cd "$repo_dir"
    git init -b main >/dev/null 2>&1 || { git init -q && git branch -M main; }
    git add .
    git commit -m "chore: bootstrap $dir scaffolding" >/dev/null 2>&1 || true
    gh repo delete "${GITHUB_USER}/${dir}" --yes >/dev/null 2>&1 || true
    gh repo create "${GITHUB_USER}/${dir}" --"${VISIBILITY}" --source="." --remote="origin" --push >/dev/null 2>&1
    echo "✓ Pushed ${dir} -> https://github.com/${GITHUB_USER}/${dir}"
  )
done

echo "=== [4/5] Initialize krs-root and add submodules ==="
mkdir -p "$ROOT_DIR/krs-root/scripts" "$ROOT_DIR/krs-root/doc"

# 自分自身を krs-root/scripts に保存（存在すれば）
if [[ -f "$ROOT_DIR/script/bootstrap-kairos.sh" ]]; then
  cp "$ROOT_DIR/script/bootstrap-kairos.sh" "$ROOT_DIR/krs-root/scripts/"
fi

cat > "$ROOT_DIR/krs-root/README.md" <<'MD'
# Kairos Root Repository
This is the root repository for Kairos. It manages all service submodules and shared documentation.
MD

cat > "$ROOT_DIR/krs-root/doc/README.md" <<'MD'
# Kairos Documentation
Project-wide bootstrap and usage documentation is stored here.
MD

cat > "$ROOT_DIR/krs-root/Kairos.code-workspace" <<'JSON'
{
  "folders": [
    { "path": "krs-infra" },
    { "path": "krs-frontend" },
    { "path": "krs-identity-gw" },
    { "path": "krs-user-profile-svc" },
    { "path": "krs-session-scheduling-svc" },
    { "path": "krs-wallet-ledger-svc" },
    { "path": "krs-notification-svc" },
    { "path": "krs-messaging-svc" },
    { "path": "krs-matching-search-svc" }
  ],
  "settings": {
    "editor.formatOnSave": true,
    "editor.tabSize": 2,
    "editor.detectIndentation": false
  }
}
JSON

(
  cd "$ROOT_DIR/krs-root"
  git init -b main >/dev/null 2>&1 || { git init -q && git branch -M main; }
  git add .
  git commit -m "chore(root): init krs-root (doc/, scripts/, workspace)" >/dev/null 2>&1 || true
  gh repo delete "${GITHUB_USER}/krs-root" --yes >/dev/null 2>&1 || true
  gh repo create "${GITHUB_USER}/krs-root" --"${VISIBILITY}" --source="." --remote="origin" --push >/dev/null 2>&1 || true

  echo "-> Adding submodules"
  subs=(
    "krs-infra"
    "krs-frontend"
    "krs-identity-gw"
    "krs-user-profile-svc"
    "krs-session-scheduling-svc"
    "krs-wallet-ledger-svc"
    "krs-notification-svc"
    "krs-messaging-svc"
    "krs-matching-search-svc"
  )
  for s in "${subs[@]}"; do
    git submodule add "https://github.com/${GITHUB_USER}/${s}.git" "${s}" >/dev/null 2>&1 || true
  done
  git commit -m "chore(root): add submodules" >/dev/null 2>&1 || true
  git push -u origin main >/dev/null 2>&1 || true
)

echo "=== [5/5] Cleanup build artifacts ==="
rm -rf "$BUILD_DIR"

echo "✅ Done. Open ./krs-root/Kairos.code-workspace in VS Code to work across all services."
