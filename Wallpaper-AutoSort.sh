#!/bin/bash
# 下にヘルプを実装してあるのじゃ

# ==========================================
# 壁紙自動整理・統合スクリプト (並列処理・ETA表示機能付き)
# Description:
#   デバイス判定と解像度選別を一括で行い、
#   スクリプトの親ディレクトリにある「壁紙転送」フォルダへ振り分けます。
#   Termux等での実行を考慮し、論理コア数に応じた並列処理を行います。
# ==========================================

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $(basename "$0")

カレントディレクトリ内の画像を分析し、以下のルールで「壁紙転送」フォルダへ移動します。
システムの論理コア数に合わせて並列処理を行い、画面下部に進捗と完了予想時間(ETA)を表示します。

[保存先構造]
    スクリプトの親フォルダ/壁紙転送/
    ├── GearS3/             (360x360)
    ├── スマホ/              (縦長, 20:9/9:16/10:16, S22Uサイズ以上)
    ├── スマホ_S22U未満/       (スマホ判定だが低解像度)
    ├── iPad Pro/           (4:3等, 長辺2388px以上)
    ├── iPad Pro_2388未満/    (iPad判定だが低解像度)
    ├── 不正ファイル/          (スマホ/iPad以外の縦画像)
    ├── パソコン/             (その他, 4K以上)
    ├── パソコン_4K未満/      (FHD以上 4K未満) [-16_9]
    └── パソコン_FHD未満/     (FHD未満) [-16_9]

Description:
    16:9のアスペクト比判定によるフォルダ分けは、パソコン用フォルダ（未満）でのみ行われます。
EOF
}

# ヘルプオプション確認
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 依存コマンド確認
command -v bc >/dev/null 2>&1 || { echo "Error: 'bc' がインストールされていません。"; exit 1; }
command -v identify >/dev/null 2>&1 || { echo "Error: 'ImageMagick' がインストールされていません。"; exit 1; }

# --- パス設定 ---

# スクリプト自身のディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# スクリプトの親ディレクトリ（ここが出力ルートの基準）
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
# 出力ルートディレクトリ
DEST_ROOT="$PARENT_DIR/壁紙転送"

echo "出力先: $DEST_ROOT"
mkdir -p "$DEST_ROOT"

# --- 処理開始 ---

# 対象ファイルをリストアップ (jpg, jpeg, png, webp)
# findコマンドでカレントディレクトリを検索
files=$(find . -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \))
total_files=$(echo "$files" | grep -v "^$" | wc -l)

if [ -z "$files" ] || [ "$total_files" -eq 0 ]; then
    echo "対象画像ファイルが見つかりませんでした。"
    exit 0
fi

# 並列数の決定 (Termux対策として最大8に制限)
MAX_JOBS=$(nproc 2>/dev/null || echo 4)
[ "$MAX_JOBS" -gt 8 ] && MAX_JOBS=8

echo "処理対象ファイル数: $total_files (並列実行数: $MAX_JOBS)"
echo "----------------------------------------"

# ログ用の一時ファイル (進捗および結果集計用)
TMP_LOG=$(mktemp)
trap 'rm -f "$TMP_LOG"' EXIT

# --- ワーカー関数 (並列で実行される処理) ---
process_image() {
    local file="$1"
    local filename=$(basename "$file")
    
    # 画像情報を取得
    local dimensions=$(identify -format "%w x %h" "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Skip:$filename" >> "$TMP_LOG"
        return
    fi
    
    local width=$(echo "$dimensions" | awk '{print $1}')
    local height=$(echo "$dimensions" | awk '{print $3}')
    local long_side=$([ "$width" -gt "$height" ] && echo "$width" || echo "$height")
    local aspect_ratio=$(echo "scale=3; $width / $height" | bc 2>/dev/null)
    
    local is_16_9=0
    if (( $(echo "$aspect_ratio > 1.77" | bc -l) )) && (( $(echo "$aspect_ratio < 1.78" | bc -l) )); then
        is_16_9=1
    fi

    # --- 振り分けロジック ---

    local dest_dir=""
    local category=""

    # 1. GearS3 (360x360 固定)
    if [ "$width" -eq 360 ] && [ "$height" -eq 360 ]; then
        dest_dir="$DEST_ROOT/GearS3"
        category="GearS3"
    # 2. スマホ (縦長 かつ アスペクト比 20:9 / 9:16 / 10:16 周辺)
    elif [ "$height" -gt "$width" ] && ( \
             ( (( $(echo "scale=3; $height / $width > 2.21" | bc -l) )) && (( $(echo "scale=3; $height / $width < 2.23" | bc -l) )) ) || \
             ( (( $(echo "scale=3; $height / $width > 1.76" | bc -l) )) && (( $(echo "scale=3; $height / $width < 1.79" | bc -l) )) ) || \
             ( (( $(echo "scale=3; $height / $width > 1.59" | bc -l) )) && (( $(echo "scale=3; $height / $width < 1.61" | bc -l) )) ) \
             ); then

        # S22U基準: 高さ 3200px
        if [ "$height" -ge 3200 ]; then
            dest_dir="$DEST_ROOT/スマホ"
            category="スマホ"
        else
            dest_dir="$DEST_ROOT/スマホ_S22U未満"
            category="スマホ_S22U未満"
        fi

    # 3. iPad Pro (アスペクト比 1.43周辺)
    elif (( $(echo "$aspect_ratio >= 1.42" | bc -l) && $(echo "$aspect_ratio <= 1.44" | bc -l) )) || \
         (( $(echo "$aspect_ratio >= 0.69" | bc -l) && $(echo "$aspect_ratio <= 0.70" | bc -l) )); then
         
        # 基準: 長辺 2388px
        if [ "$long_side" -ge 2388 ]; then
            dest_dir="$DEST_ROOT/iPad Pro"
            category="iPad Pro"
        else
            dest_dir="$DEST_ROOT/iPad Pro_2388未満"
            category="iPad Pro_2388未満"
        fi

    # 4. 不正ファイル (スマホ/iPadに該当しない縦画像)
    elif [ "$height" -gt "$width" ]; then
        dest_dir="$DEST_ROOT/不正ファイル"
        category="不正ファイル"

    # 5. パソコン (上記以外)
    else
        # 閾値設定 (16:9かどうかで判定基準が変わる)
        local th_4k=2400
        local th_fhd=1200
        if [ "$is_16_9" -eq 1 ]; then
            th_4k=2160
            th_fhd=1080
        fi
        
        # 判定
        if [ "$height" -ge "$th_4k" ]; then
            # 4K以上
            dest_dir="$DEST_ROOT/パソコン"
            category="パソコン"
        elif [ "$height" -ge "$th_fhd" ]; then
            # 4K未満 FHD以上
            dest_dir="$DEST_ROOT/パソコン_4K未満"
            category="パソコン_4K未満"
            [ "$is_16_9" -eq 1 ] && dest_dir="${dest_dir}-16_9" && category="${category}-16_9"
        else
            # FHD未満
            dest_dir="$DEST_ROOT/パソコン_FHD未満"
            category="パソコン_FHD未満"
            [ "$is_16_9" -eq 1 ] && dest_dir="${dest_dir}-16_9" && category="${category}-16_9"
        fi
    fi

    # 移動実行と結果記録
    if [ -n "$dest_dir" ]; then
        mkdir -p "$dest_dir"
        mv "$file" "$dest_dir/"
        echo "$category" >> "$TMP_LOG"
    fi
}

# --- 進捗表示関数 ---
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
        
        printf "\r\033[K[ %d/%d ] %3d%% | ETA: %s | 並列処理中..." "$current" "$total_files" "$percent" "$eta_formatted"
        
        if [ "$current" -ge "$total_files" ]; then
            break
        fi
        sleep 0.5
    done
}

# 進捗プロセスをバックグラウンドで開始
monitor_progress &
MONITOR_PID=$!

# ジョブ制御メインループ
while read -r file; do
    [ -z "$file" ] && continue
    process_image "$file" &
    
    # MONITOR_PIDもjobsに含まれるため、MAX_JOBS + 1を基準にする
    while [ $(jobs -pr | wc -l) -ge $((MAX_JOBS + 1)) ]; do
        wait -n 2>/dev/null
    done
done <<< "$files"

# すべてのワーカープロセスが完了するのを待機
wait

# 進捗表示プロセスが残っていれば終了させる
kill $MONITOR_PID 2>/dev/null
printf "\r\033[K" 
echo "----------------------------------------"

# --- 結果集計 ---
count_gears3=$(grep -c "^GearS3" "$TMP_LOG" || echo 0)
count_phone=$(grep -c "^スマホ$" "$TMP_LOG" || echo 0)
count_phone_low=$(grep -c "^スマホ_S22U未満" "$TMP_LOG" || echo 0)
count_ipad=$(grep -c "^iPad Pro$" "$TMP_LOG" || echo 0)
count_ipad_low=$(grep -c "^iPad Pro_2388未満" "$TMP_LOG" || echo 0)
count_invalid=$(grep -c "^不正ファイル" "$TMP_LOG" || echo 0)
count_pc_4k=$(grep -c "^パソコン$" "$TMP_LOG" || echo 0)
count_pc_mid=$(grep -c "^パソコン_4K未満" "$TMP_LOG" || echo 0)
count_pc_low=$(grep -c "^パソコン_FHD未満" "$TMP_LOG" || echo 0)
skip_count=$(grep -c "^Skip:" "$TMP_LOG" || echo 0)

echo "処理完了。出力先: $DEST_ROOT"
echo "総ファイル数: $total_files"
echo "経過時間: $(printf "%02d:%02d" $((SECONDS/60)) $((SECONDS%60)))"
echo ""
echo "【内訳】"
echo "  GearS3 : $count_gears3"
echo "  スマホ : $count_phone"
echo "  スマホ_S22U未満 : $count_phone_low"
echo "  iPad Pro : $count_ipad"
echo "  iPad Pro_2388未満 : $count_ipad_low"
echo "  不正ファイル : $count_invalid"
echo "  パソコン : $count_pc_4k"
echo "  パソコン_4K未満(※-16_9含む) : $count_pc_mid"
echo "  パソコン_FHD未満(※-16_9含む) : $count_pc_low"
[ "$skip_count" -gt 0 ] && echo "  読込エラー/スキップ : $skip_count"
echo "----------------------------------------"