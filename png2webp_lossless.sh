#!/bin/bash
# 下にヘルプを実装してあるのじゃ

# =============================================================================
# PNG → ロスレスWebP 変換スクリプト (並列処理・ETA表示機能付き)
# Description:
#   カレントディレクトリを再帰的に探索し、PNG をロスレス WebP に変換する。
#   メタデータ（タグ・更新時刻等）をすべて引き継ぎ、
#   変換・検証に成功したファイルのみ元の PNG を削除する。
#   論理コア数に応じた並列処理を行う。
# =============================================================================

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $(basename "$0") [オプション]

カレントディレクトリ以下の PNG ファイルを再帰的に探索し、
ロスレス WebP に変換します。
システムの論理コア数に合わせて並列処理を行い、進捗と完了予想時間(ETA)を表示します。

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
    --single        直列（シングルスレッド）で処理する

[依存コマンド]
    magick (ImageMagick 7)
    exiftool

[実行例]
    # 対象フォルダに移動して実行
    cd /mnt/Linux_Data/壁紙作成用のバックアップ/未整理
    $(basename "$0")

    # 確認だけ行う
    $(basename "$0") --dry-run

    # シングルスレッドで実行
    $(basename "$0") --single
EOF
}

main() {
    # ── 引数解析 ──────────────────────────────────────────────
    OPT_DRY_RUN=false
    OPT_SINGLE=false

    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                show_help
                exit 0
                ;;
            --dry-run)
                OPT_DRY_RUN=true
                ;;
            --single)
                OPT_SINGLE=true
                ;;
            *)
                echo "エラー: 不明な引数 '$arg'" >&2
                echo "使い方を確認するには: $0 --help" >&2
                exit 1
                ;;
        esac
    done

    # ── 依存コマンド確認 ──────────────────────────────────────
    command -v magick >/dev/null 2>&1 || { error "'magick' (ImageMagick 7) がインストールされていません。"; exit 1; }
    command -v exiftool >/dev/null 2>&1 || { error "'exiftool' がインストールされていません。"; exit 1; }

    # ── パス設定 ──────────────────────────────────────────────
    TARGET_DIR="$(pwd)"

    # ── 対象ファイルをリストアップ ─────────────────────────────
    TMP_FILES=$(mktemp)
    find "$TARGET_DIR" -type f -iname '*.png' -print0 | sort -z > "$TMP_FILES"

    # ファイル数をカウント
    total_files=$(tr -cd '\0' < "$TMP_FILES" | wc -c)

    if [ "$total_files" -eq 0 ]; then
        echo "対象の PNG ファイルが見つかりませんでした。"
        rm -f "$TMP_FILES"
        exit 0
    fi

    # ── 並列数の決定 (最大8に制限) ────────────────────────────
    MAX_JOBS=$(nproc 2>/dev/null || echo 4)
    [ "$MAX_JOBS" -gt 8 ] && MAX_JOBS=8

    if [ "$OPT_DRY_RUN" = "true" ]; then
        info "=== DRY RUN モード（実際には何も変更しません） ==="
    fi

    echo "=========================================="
    echo "PNG → ロスレス WebP 変換開始"
    echo "対象ディレクトリ: ${TARGET_DIR}"
    echo "処理対象ファイル数: $total_files (並列実行数: $MAX_JOBS)"
    echo "=========================================="

    # ── 進捗追跡用の一時ファイル ──────────────────────────────
    TMP_LOG=$(mktemp)
    trap 'rm -f "$TMP_LOG" "$TMP_FILES"' EXIT

    # ── dry-run 時は直列でリスト表示のみ ─────────────────────
    if [ "$OPT_DRY_RUN" = "true" ]; then
        while IFS= read -r -d '' png_file; do
            webp_file="${png_file%.png}.webp"
            dry "magick \"$png_file\" -define webp:lossless=true \"$webp_file\""
        done < "$TMP_FILES"

        echo "=========================================="
        echo "DRY RUN 完了: ${total_files} ファイルが変換対象"
        echo "=========================================="
        return 0
    fi

    # ── 進捗表示関数 ──────────────────────────────────────────
    monitor_progress() {
        local start_sec=$SECONDS
        while true; do
            local current=$(wc -l < "$TMP_LOG" 2>/dev/null || echo 0)
            local current_sec=$((SECONDS - start_sec))
            local eta_formatted="--:--"

            if [ "$current" -gt 0 ]; then
                local avg_sec=$(echo "scale=4; $current_sec / $current" | bc)
                local remain=$((total_files - current))
                local eta_sec=$(echo "$remain * $avg_sec" | bc | awk '{printf("%d",$1 + 0.5)}')
                if [ "$eta_sec" -ge 3600 ]; then
                     eta_formatted=$(printf "%02d:%02d:%02d" $((eta_sec/3600)) $(( (eta_sec%3600)/60 )) $((eta_sec%60)))
                else
                     eta_formatted=$(printf "%02d:%02d" $((eta_sec/60)) $((eta_sec%60)))
                fi
            fi

            local percent=0
            [ "$total_files" -gt 0 ] && percent=$(( current * 100 / total_files ))

            if [ "$OPT_SINGLE" = "true" ]; then
                printf "\r\033[K[ %d/%d ] %3d%% | ETA: %s | 直列処理中..." "$current" "$total_files" "$percent" "$eta_formatted"
            else
                printf "\r\033[K[ %d/%d ] %3d%% | ETA: %s | 並列処理中..." "$current" "$total_files" "$percent" "$eta_formatted"
            fi

            if [ "$current" -ge "$total_files" ]; then
                break
            fi
            sleep 0.5
        done
    }

    # ── ワーカー関数 (並列で実行される処理) ───────────────────
    process_image() {
        local png_file="$1"
        local webp_file="${png_file%.png}.webp"

        # 同名の .webp が既に存在する場合はスキップ
        if [[ -f "$webp_file" ]]; then
            echo "SKIP:${png_file}" >> "$TMP_LOG"
            return
        fi

        # 1. 元ファイルの更新日時を保存
        local original_mtime
        original_mtime=$(stat -c '%Y' "$png_file" 2>/dev/null) || {
            echo "FAIL:${png_file}" >> "$TMP_LOG"
            return
        }

        # 2. ImageMagick でロスレス WebP に変換
        if ! magick "$png_file" -define webp:lossless=true "$webp_file" 2>/dev/null; then
            rm -f "$webp_file"
            echo "FAIL:${png_file}" >> "$TMP_LOG"
            return
        fi

        # 3. 出力ファイルが存在し、サイズが 0 でないことを確認
        if [[ ! -s "$webp_file" ]]; then
            rm -f "$webp_file"
            echo "FAIL:${png_file}" >> "$TMP_LOG"
            return
        fi

        # 4. 画像の整合性を確認（デコード可能か）
        if ! magick identify "$webp_file" &>/dev/null; then
            rm -f "$webp_file"
            echo "FAIL:${png_file}" >> "$TMP_LOG"
            return
        fi

        # 5. exiftool で元 PNG から全メタデータをコピー
        if ! exiftool -overwrite_original -TagsFromFile "$png_file" -All:All "$webp_file" 2>/dev/null; then
            rm -f "$webp_file"
            echo "FAIL:${png_file}" >> "$TMP_LOG"
            return
        fi

        # 6. メタデータの引き継ぎを検証
        local src_meta_count dst_meta_count
        src_meta_count=$(exiftool -s -s -s -G -All "$png_file" 2>/dev/null | \
            grep -v -E '^\[File\]|^\[System\]' | wc -l)
        dst_meta_count=$(exiftool -s -s -s -G -All "$webp_file" 2>/dev/null | \
            grep -v -E '^\[File\]|^\[System\]' | wc -l)

        if [[ "$src_meta_count" -gt 0 && "$dst_meta_count" -eq 0 ]]; then
            rm -f "$webp_file"
            echo "FAIL:${png_file}" >> "$TMP_LOG"
            return
        fi

        # 7. ファイルシステムのタイムスタンプを復元
        touch -d "@${original_mtime}" "$webp_file" 2>/dev/null

        # 8. すべて成功 → 元 PNG を削除
        rm -f "$png_file"
        echo "OK:${png_file}" >> "$TMP_LOG"
    }

    # ── 進捗プロセスをバックグラウンドで開始 ───────────────────
    monitor_progress &
    MONITOR_PID=$!

    # ── メインループ ─────────────────────────────────────────
    if [ "$OPT_SINGLE" = "true" ]; then
        # シングルスレッド処理
        while IFS= read -r -d '' png_file; do
            process_image "$png_file"
        done < "$TMP_FILES"
    else
        # マルチスレッド処理
        while IFS= read -r -d '' png_file; do
            process_image "$png_file" &

            # MONITOR_PID も jobs に含まれるため MAX_JOBS + 1 を基準にする
            while [ $(jobs -pr | wc -l) -ge $((MAX_JOBS + 1)) ]; do
                wait -n 2>/dev/null
            done
        done < "$TMP_FILES"
    fi

    # すべてのワーカープロセスが完了するのを待機
    wait

    # 進捗表示プロセスが残っていれば終了させる
    kill $MONITOR_PID 2>/dev/null
    printf "\r\033[K"

    # ── 結果集計 ──────────────────────────────────────────────
    count_ok=$(( $(grep -c "^OK:" "$TMP_LOG" 2>/dev/null) + 0 ))
    count_fail=$(( $(grep -c "^FAIL:" "$TMP_LOG" 2>/dev/null) + 0 ))
    count_skip=$(( $(grep -c "^SKIP:" "$TMP_LOG" 2>/dev/null) + 0 ))

    echo "=========================================="
    echo "変換完了"
    echo "  合計:    ${total_files} ファイル"
    echo "  成功:    ${count_ok} ファイル"
    echo "  失敗:    ${count_fail} ファイル"
    echo "  スキップ: ${count_skip} ファイル"
    echo "  経過時間: $(printf "%02d:%02d" $((SECONDS/60)) $((SECONDS%60)))"
    echo "=========================================="

    # 失敗ファイルがあれば一覧を表示
    if [ "$count_fail" -gt 0 ]; then
        echo ""
        echo "【失敗ファイル一覧】"
        grep "^FAIL:" "$TMP_LOG" | sed 's/^FAIL:/  /'
    fi
    if [ "$count_skip" -gt 0 ]; then
        echo ""
        echo "【スキップ一覧（同名 .webp が既存）】"
        grep "^SKIP:" "$TMP_LOG" | sed 's/^SKIP:/  /'
    fi
}

# =============================================================================
# ユーティリティ
# =============================================================================
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*" >&2; }
error()   { echo "[ERROR] $*" >&2; }
dry()     { echo "[DRY]   $*"; }

main "$@"
