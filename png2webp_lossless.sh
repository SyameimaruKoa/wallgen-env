#!/bin/bash
# ==============================================================================
# PNG → ロスレスWebP 変換スクリプト (GNU Parallel並列処理)
# Description:
#   カレントディレクトリを再帰的に探索し、PNG をロスレス WebP に変換する。
#   メタデータ（タグ・更新時刻等）をすべて引き継ぎ、
#   変換・検証に成功したファイルのみ元の PNG を削除する。
#   GNU Parallelで並列処理を行う。
#
# ※下にヘルプがあるぞ。詳しい使い方は show_help 関数を参照するのじゃ。
# ==============================================================================

# --- システムコア数の取得 (OMP_NUM_THREADSの罠を回避するため --all を使うぞ！) ---
export SYSTEM_CORES=$(nproc --all 2>/dev/null || nproc 2>/dev/null || echo 4)

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $(basename "$0") [オプション]

カレントディレクトリ以下の PNG ファイルを再帰的に探索し、
ロスレス WebP に変換するのじゃ。
GNU Parallelで並列処理を行い、進捗バーを表示するぞ。

[動作フロー]
    1. find で PNG を再帰探索
    2. ImageMagick でロスレス WebP に変換
    3. 出力ファイルの整合性を検証 (magick identify)
    4. exiftool で全メタデータを PNG → WebP にコピー
    5. メタデータの引き継ぎを検証
    6. ファイルシステムのタイムスタンプ（更新日時）を復元
    7. すべて成功した場合のみ元 PNG を削除

[オプション]
    -h, --help      このヘルプを表示して終了する
    --dry-run       実際には何も変更せず、実行内容を表示する
    -j, --jobs [n]  並列実行数。指定しない場合はコア数を使うのじゃ。

[依存コマンド]
    magick (ImageMagick 7)
    exiftool
    parallel (GNU Parallel)

[実行例]
    # 対象フォルダに移動して実行
    cd /mnt/Linux_Data/壁紙作成用のバックアップ/未整理
    $(basename "$0")

    # 確認だけ行う
    $(basename "$0") --dry-run

    # 並列数を指定して実行
    $(basename "$0") -j 4
EOF
}

# --- 関数: 変換処理のコア部分 (Parallelから呼び出すためexportする) ---
process_image() {
    local png_file="$1"
    local webp_file="${png_file%.png}.webp"

    local original_size_bytes=$(stat -c%s "$png_file" 2>/dev/null || echo 0)
    local original_size_h=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$original_size_bytes" 2>/dev/null || echo "${original_size_bytes}B")

    echo "───────────────処理開始: $png_file ($original_size_h)───────────────"

    # 同名の .webp が既に存在する場合は削除して再作成
    if [[ -f "$webp_file" ]]; then
        rm -f "$webp_file"
    fi

    # 1. 元ファイルの更新日時を保存
    local original_mtime
    original_mtime=$(stat -c '%Y' "$png_file" 2>/dev/null) || {
        echo "  !!! エラー: stat失敗 $(basename "$png_file")"
        return 1
    }

    # 2. ImageMagick でロスレス WebP に変換
    if ! magick "$png_file" -define webp:lossless=true "$webp_file" 2>/dev/null; then
        rm -f "$webp_file"
        echo "  !!! エラー: $(basename "$png_file") の変換に失敗。"
        return 1
    fi

    # 3. 出力ファイルが存在し、サイズが 0 でないことを確認
    if [[ ! -s "$webp_file" ]]; then
        rm -f "$webp_file"
        echo "  !!! エラー: $(basename "$png_file") の出力ファイルが空。"
        return 1
    fi

    # 4. 画像の整合性を確認（デコード可能か）
    if ! magick identify "$webp_file" &>/dev/null; then
        rm -f "$webp_file"
        echo "  !!! エラー: $(basename "$png_file") の整合性検証に失敗。"
        return 1
    fi

    # 5. exiftool で元 PNG から全メタデータをコピー
    if ! exiftool -overwrite_original -TagsFromFile "$png_file" -All:All "$webp_file" >/dev/null 2>&1; then
        rm -f "$webp_file"
        echo "  !!! エラー: $(basename "$png_file") のメタデータコピーに失敗。"
        return 1
    fi

    # 6. メタデータの引き継ぎを検証
    local src_meta_count dst_meta_count
    src_meta_count=$(exiftool -s -s -s -G -All "$png_file" 2>/dev/null | \
        grep -v -E '^\[File\]|^\[System\]' | wc -l)
    dst_meta_count=$(exiftool -s -s -s -G -All "$webp_file" 2>/dev/null | \
        grep -v -E '^\[File\]|^\[System\]' | wc -l)

    if [[ "$src_meta_count" -gt 0 && "$dst_meta_count" -eq 0 ]]; then
        rm -f "$webp_file"
        echo "  !!! エラー: $(basename "$png_file") のメタデータ引き継ぎ検証に失敗。"
        return 1
    fi

    # 7. ファイルシステムのタイムスタンプを復元
    touch -d "@${original_mtime}" "$webp_file" 2>/dev/null

    # 8. すべて成功 → 元 PNG を削除
    local converted_size_bytes=$(stat -c%s "$webp_file" 2>/dev/null || echo 0)
    local converted_size_h=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$converted_size_bytes" 2>/dev/null || echo "${converted_size_bytes}B")

    if [ "$original_size_bytes" -gt 0 ]; then
        local size_percentage=$(echo "scale=2; $converted_size_bytes * 100 / $original_size_bytes" | bc)
        echo "  [webp] 成功: $(basename "$webp_file") ${converted_size_h} (${size_percentage}%)"
    fi

    rm -f "$png_file"
}
export -f process_image

# ==============================================================================
# --- メイン処理 ---
# ==============================================================================

OPT_DRY_RUN=false
JOBS=""

# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        --dry-run) OPT_DRY_RUN=true; shift ;;
        -j|--jobs) JOBS="$2"; shift 2 ;;
        *)
            echo "エラー: 不明な引数 '$1'" >&2
            echo "使い方を確認するには: $0 --help" >&2
            exit 1
            ;;
    esac
done

# 依存コマンド確認
if ! command -v magick > /dev/null 2>&1; then
    echo "エラー: 必須コマンド 'magick' (ImageMagick 7) が見つかりません。" >&2
    exit 1
fi
if ! command -v exiftool > /dev/null 2>&1; then
    echo "エラー: 必須コマンド 'exiftool' が見つかりません。" >&2
    exit 1
fi
if ! command -v parallel > /dev/null; then
    echo "エラー: GNU Parallel が入っておらん。sudo apt install parallel などでインストールせい。" >&2
    exit 1
fi

# ── パス設定 ──────────────────────────────────────────────────
TARGET_DIR="$(pwd)"

# ── 対象ファイルをリストアップ ─────────────────────────────────
TMP_FILES=$(mktemp)
trap 'rm -f "$TMP_FILES"' EXIT
find "$TARGET_DIR" -type f -iname '*.png' -print0 | sort -z > "$TMP_FILES"

# ファイル数をカウント
total_files=$(tr -cd '\0' < "$TMP_FILES" | wc -c)

if [ "$total_files" -eq 0 ]; then
    echo "対象の PNG ファイルが見つかりませんでした。"
    rm -f "$TMP_FILES"
    exit 0
fi

# ── 並列数の決定 ──────────────────────────────────────────────
CALC_JOBS="$JOBS"
if [ -z "$CALC_JOBS" ]; then
    CALC_JOBS="$SYSTEM_CORES"
fi

# ── dry-run 時は直列でリスト表示のみ ──────────────────────────
if [ "$OPT_DRY_RUN" = "true" ]; then
    echo "=== DRY RUN モード（実際には何も変更しません） ==="
    echo "=========================================="
    echo "PNG → ロスレス WebP 変換"
    echo "対象ディレクトリ: ${TARGET_DIR}"
    echo "処理対象ファイル数: $total_files"
    echo "=========================================="

    while IFS= read -r -d '' png_file; do
        webp_file="${png_file%.png}.webp"
        echo "[DRY]   magick \"$png_file\" -define webp:lossless=true \"$webp_file\""
    done < "$TMP_FILES"

    echo "=========================================="
    echo "DRY RUN 完了: ${total_files} ファイルが変換対象"
    echo "=========================================="
    exit 0
fi

echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"
echo "PNG → ロスレス WebP 並列変換開始じゃ！"
echo "対象ディレクトリ: ${TARGET_DIR}"
echo "処理対象ファイル数: $total_files (並列実行数: $CALC_JOBS)"
echo "☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆☆"

# ── GNU Parallel で並列実行 ───────────────────────────────────
cat "$TMP_FILES" | parallel --null -j "$CALC_JOBS" --bar process_image {}

echo "全ての処理が完了したのじゃ！"
