# Kairos セットアップ手順

## 1.1. Homebrew & VS Code インストール

```bash
# Homebrew インストール
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# VS Code インストール
brew install --cask visual-studio-code

# 確認
which code
code --version
```

> `code` コマンドが無い場合: VS Code 起動 → `⌘⇧P` → 「Shell Command: Install 'code' command in PATH」を実行。

---

## 1.2. Kairos 用ディレクトリ作成

```bash
mkdir -p ~/Applications/Kairos
cd ~/Applications/Kairos
```

---

## 1.3. 必須ツールの導入

```bash
# 基本
brew install git gh jq direnv make

# Node.js (Volta推奨)
curl https://get.volta.sh | bash
volta install node@20 yarn@1 pnpm@9 npm@latest

# Java (SDKMAN!)
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 21.0.4-tem
sdk install maven 3.9.9
sdk install gradle 8.10

# Docker (Colima)
brew install colima docker
colima start --cpu 4 --memory 8 --disk 60

# AWS CLI & CDK
brew install awscli
npm i -g aws-cdk@2


# nvm
brew install nvm
mkdir ~/.nvm
echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
echo '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"' >> ~/.zshrc
source ~/.zshrc

# Node.js TLS
nvm install --lts
nvm use --lts
```

---

## 1.4. VS Code 推奨拡張機能

```bash
# Core
code --install-extension ms-vscode.vscode-typescript-next
code --install-extension dbaeumer.vscode-eslint
code --install-extension esbenp.prettier-vscode
code --install-extension usernamehw.errorlens
code --install-extension orta.vscode-jest

# React/Node
code --install-extension bradlc.vscode-tailwindcss
code --install-extension YoavBls.pretty-ts-errors

# Java/Spring Boot
code --install-extension vscjava.vscode-java-pack
code --install-extension vmware.vscode-spring-boot
code --install-extension GabrielBB.vscode-lombok

# Docker / AWS
code --install-extension ms-azuretools.vscode-docker
code --install-extension amazonwebservices.aws-toolkit-vscode

# Docs
code --install-extension eamodio.gitlens
code --install-extension yzhang.markdown-all-in-one
code --install-extension bierner.markdown-mermaid
```

---

## 2. GitHub ログイン（HTTPS）

```bash
gh auth login
```

選択肢:
- GitHub.com  
- HTTPS  
- ブラウザで認可  

確認:
```bash
gh auth status
```

---

## 3. Git の基本設定（未設定なら）

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

---

## 4. ルートリポジトリの作成（以降の手順はリポジトリ構築手順のため実施不要）

GitHub 上で **kairos-root** を作成（README 付き）:

```bash
gh repo create kairos-root   --public   --add-readme   --description "Kairos workspace (polyrepo root)"   --confirm
```

---

## 5. ローカルへのクローン

```bash
mkdir -p ~/Applications
git clone "https://github.com/katsuki-ito-10/kairos-root.git" ~/Applications/Kairos
cd ~/Applications/Kairos
```

---

## 6. 環境変数ファイルの作成

`.env`（**コミット禁止**）を作成:

```bash
cat > .env <<'EOF'
OWNER=katsuki-ito-10
VISIBILITY=public
BASE_DIR=/Users/<あなたのmacユーザー名>/Applications/Kairos
EOF
```

`.env.example`（共有用サンプル）:

```bash
OWNER=
VISIBILITY=public
BASE_DIR=
```

---

## 7. スクリプト配置と権限付与

1. `scripts/` ディレクトリを作成し、以下2ファイルを配置する:  
   - `scripts/bootstrap-kairos.sh`  
   - `scripts/generate-docs.sh`  

2. 実行権限を付与:
```bash
chmod +x scripts/*.sh
```

> このセットアップでは、docs/ の Markdown 自動生成と、各リポジトリの GitHub 作成＋HTTPS クローンを行います。

---

## 8. スクリプト実行

### 8.1 既存リポジトリを削除して再作成する場合
```bash
scripts/bootstrap-kairos.sh
```

### 8.2 既存を残して利用する場合
```bash
scripts/bootstrap-kairos.sh --keep
```

### 8.3 オプション例
```bash
scripts/bootstrap-kairos.sh --gitignore Node --add-license mit
```

> **Note:** 既存リポジトリを削除するモードで 403 が出る場合は、次を実行して権限を付与してください：  
> `gh auth refresh -h github.com -s delete_repo`

---

## 9. コミット（`.env` は除外）

```bash
git add .gitignore .env.example scripts README.md kairos.code-workspace docs
git commit -m "chore(root): bootstrap repos and generate docs"
git push origin HEAD
```

---

## 10. 実行結果

- `docs/setup/` : 初回準備・GitHub 認証・VS Code インストール手順  
- `docs/security/` : .env 運用ルール  
- 各サービスリポジトリ（例: `krs-infra`, `krs-frontend` …）が GitHub 上に作成され、HTTPS クローンされる  
- ルートに `kairos.code-workspace` が生成される  

---

## 付録: トラブルシュート

- **`code` コマンドが無い**: VS Code を起動 → `⌘⇧P` → “Shell Command: Install 'code' command in PATH”。  
- **既存リポジトリ削除で 403**: `gh auth refresh -h github.com -s delete_repo`。  
- **Colima 起動時のリソース不足**: `colima start --cpu 4 --memory 8 --disk 60` の値を下げて再実行。  
- **AWS CLI が見つからない**: `brew reinstall awscli`。  
