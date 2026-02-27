#!/bin/sh
# setup-illust-env.sh
# ヘルプは末尾の show_help() を参照。

# =============================================================================
# 定数
# =============================================================================
REPO_URL="https://github.com/SyameimaruKoa/wallgen-env.git"

# UID で判定: Termux はアプリ UID (>=10000)、root は 0
# PATH に Termux が通っていても UID は変わらないため誤判定しない
if [ "$(id -u)" -ge 10000 ]; then
    ENV_TYPE="termux"
    SDCARD_BASE="/data/data/com.termux/files/home/storage/shared"
else
    ENV_TYPE="root"
    SDCARD_BASE="/sdcard"
fi

BASE_DIR="${SDCARD_BASE}/イラスト編集用"
SCRIPT_DIR="${BASE_DIR}/Script"

# =============================================================================
# ヘルプ（下部に詳細定義）
# =============================================================================
show_help() {
    cat <<EOF
使い方:
  setup-illust-env.sh [オプション]

説明:
  イラスト編集用のフォルダ構成を作成し、
  Script/ フォルダ内に SyameimaruKoa/wallgen-env リポジトリを clone する。
  Termux または root/adb shell 環境での実行を想定している。

  ベースパスは実行環境により自動で切り替わる:
    Termux    : /data/data/com.termux/files/home/storage/shared/イラスト編集用
    root/adb  : /sdcard/イラスト編集用

  作成されるフォルダ構成（ベースパス以下）:
    イラスト編集用/
    ├── Photo Editor/
    ├── Script/
    │   └── (wallgen-env が clone される)
    ├── 壁紙転送/
    ├── 整理済み/
    │   ├── イラスト/
    │   ├── 裏イラスト/
    │   ├── 公式/
    │   ├── 移動用/
    │   └── 素材/
    └── 未整理/
        ├── Twitter/
        └── pixiv/

オプション:
  -h, --help      このヘルプを表示して終了する
  --no-clone      git clone をスキップし、フォルダ作成のみ行う
  --dry-run       実際には何も変更せず、実行内容を表示する

実行例:
  # 通常実行（フォルダ作成 + clone）
  sh setup-illust-env.sh

  # フォルダ作成だけ行う
  sh setup-illust-env.sh --no-clone

  # 実際には何もせず確認だけ
  sh setup-illust-env.sh --dry-run

注意:
  - Termux で実行する場合:
      storage/shared を使うため termux-setup-storage を先に実行すること。
      git がなければ: pkg install git
  - root / adb shell で実行する場合:
      /sdcard に直接アクセスするため特別な設定は不要。
      git がなければ環境に応じてインストール (apt install git 等)。
EOF
}

# =============================================================================
# 引数解析
# =============================================================================
OPT_NO_CLONE=false
OPT_DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        --no-clone)
            OPT_NO_CLONE=true
            ;;
        --dry-run)
            OPT_DRY_RUN=true
            ;;
        *)
            echo "エラー: 不明な引数 '$arg'" >&2
            echo "使い方を確認するには: $0 --help" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# ユーティリティ
# =============================================================================
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*" >&2; }
error()   { echo "[ERROR] $*" >&2; }

run_cmd() {
    # dry-run 時はコマンドを表示するだけ
    if [ "$OPT_DRY_RUN" = "true" ]; then
        echo "[DRY]   $*"
    else
        "$@"
    fi
}

# =============================================================================
# 前提確認
# =============================================================================
check_sdcard_access() {
    if [ "$OPT_DRY_RUN" = "true" ]; then
        info "dry-run: ストレージアクセス確認をスキップ (ENV=${ENV_TYPE}, BASE=${BASE_DIR})"
        return 0
    fi

    info "実行環境: ${ENV_TYPE}  ベースパス: ${BASE_DIR}"

    if [ "$ENV_TYPE" = "termux" ]; then
        if [ ! -d "$SDCARD_BASE" ]; then
            error "${SDCARD_BASE} が見つかりません。"
            error "Termux で termux-setup-storage を先に実行してください。"
            exit 1
        fi
    else
        if [ ! -d "/sdcard" ]; then
            error "/sdcard が見つかりません。"
            exit 1
        fi
    fi

    # 書き込みテスト
    test_file="${SDCARD_BASE}/.setup_write_test_$$"
    if ! touch "$test_file" >/dev/null 2>&1; then
        error "${SDCARD_BASE} への書き込み権限がありません。"
        if [ "$ENV_TYPE" = "termux" ]; then
            error "termux-setup-storage を先に実行してください。"
        fi
        exit 1
    fi
    rm -f "$test_file"
}

check_git() {
    if ! command -v git >/dev/null 2>&1; then
        warn "git コマンドが見つかりません。"
        if [ "$ENV_TYPE" = "termux" ]; then
            warn "Termux の場合: pkg install git"
        else
            warn "root 環境: apt install git などでインストールしてください。"
        fi
        return 1
    fi
    return 0
}

# =============================================================================
# メイン処理
# =============================================================================
main() {
    if [ "$OPT_DRY_RUN" = "true" ]; then
        info "=== DRY RUN モード（実際には何も変更しません） ==="
    fi

    # ストレージアクセス確認
    check_sdcard_access

    # ── フォルダ作成 ──────────────────────────────────────────────
    info "フォルダ構成を作成します..."
    created=0
    skipped=0

    # heredoc でフォルダ一覧を列挙（スペース入りパス対応、配列不要）
    while IFS= read -r dir; do
        if [ -d "$dir" ]; then
            info "既存: $dir"
            skipped=$((skipped + 1))
        else
            run_cmd mkdir -p "$dir"
            if [ "$OPT_DRY_RUN" = "true" ] || [ -d "$dir" ]; then
                success "作成: $dir"
                created=$((created + 1))
            else
                error "作成失敗: $dir"
            fi
        fi
    done <<EOF
${BASE_DIR}/Photo Editor
${BASE_DIR}/Script
${BASE_DIR}/壁紙転送
${BASE_DIR}/整理済み/イラスト
${BASE_DIR}/整理済み/裏イラスト
${BASE_DIR}/整理済み/公式
${BASE_DIR}/整理済み/移動用
${BASE_DIR}/整理済み/素材
${BASE_DIR}/未整理/Twitter
${BASE_DIR}/未整理/pixiv
EOF

    info "フォルダ: ${created} 件作成、${skipped} 件スキップ"

    # ── git clone ─────────────────────────────────────────────────
    if [ "$OPT_NO_CLONE" = "true" ]; then
        info "--no-clone が指定されたため、git clone をスキップします。"
        return 0
    fi

    if ! check_git; then
        warn "git が使えないため clone をスキップします。"
        warn "後で手動で clone するか、--no-clone を外して再実行してください。"
        return 0
    fi

    if [ -d "${SCRIPT_DIR}/.git" ]; then
        info "既にリポジトリが存在します: ${SCRIPT_DIR}"
        info "git pull で更新を試みます..."
        run_cmd git -C "${SCRIPT_DIR}" pull
    else
        info "リポジトリを clone します: ${REPO_URL}"
        run_cmd git clone "${REPO_URL}" "${SCRIPT_DIR}"
    fi

    if [ "$OPT_DRY_RUN" = "true" ] || [ -d "${SCRIPT_DIR}" ]; then
        success "セットアップ完了！"
        if [ "$OPT_DRY_RUN" != "true" ]; then
            echo ""
            echo "  スクリプトの場所: ${SCRIPT_DIR}"
            echo "  ベースフォルダ  : ${BASE_DIR}"
        fi
    fi
}

main "$@"
