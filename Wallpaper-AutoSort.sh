#!/bin/bash

# ==========================================
# 壁紙自動整理・統合スクリプト (ETA表示機能付き)
# Description:
#   デバイス判定と解像度選別を一括で行い、
#   スクリプトの親ディレクトリにある「壁紙転送」フォルダへ振り分けます。
#   進捗状況と完了予想時間をリアルタイムで表示します。
# ==========================================

# --- 初期設定 ---

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $(basename "$0")

カレントディレクトリ内の画像を分析し、以下のルールで「壁紙転送」フォルダへ移動します。
画面下部に進捗と完了予想時間(ETA)を表示します。

[保存先構造]
    スクリプトの親フォルダ/壁紙転送/
    ├── GearS3/             (360x360)
    ├── スマホ/              (縦長, S22Uサイズ以上)
    ├── スマホ_S22U未満/       (スマホ判定だが低解像度)
    ├── iPad Pro/           (4:3等, 長辺2388px以上)
    ├── iPad Pro_2388未満/    (iPad判定だが低解像度)
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

# ファイル数カウント
total_files=$(echo "$files" | wc -l)
if [ -z "$files" ] || [ "$total_files" -eq 0 ]; then
    echo "対象画像ファイルが見つかりませんでした。"
    exit 0
fi

echo "処理対象ファイル数: $total_files"
echo "----------------------------------------"

# 時間計測用
SECONDS=0
count=0

# 集計用変数
count_gears3=0
count_phone=0
count_ipad=0
count_pc=0
count_lowres=0

# ループ処理
while read -r file; do
    # 空行対策
    if [ -z "$file" ]; then continue; fi
    
    count=$((count + 1))
    
    # --- ETA (完了予想時間) 計算 ---
    current_sec=$SECONDS
    if [ "$count" -gt 1 ] && [ "$current_sec" -gt 0 ]; then
        # 1ファイルあたりの平均秒数
        avg_sec=$(echo "scale=4; $current_sec / ($count - 1)" | bc)
        # 残りファイル数
        remain_files=$((total_files - count))
        # 残り秒数
        eta_sec=$(echo "$remain_files * $avg_sec" | bc | awk '{printf("%d",$1 + 0.5)}')
        # MM:SS 形式に変換
        eta_formatted=$(printf "%02d:%02d" $((eta_sec/60)) $((eta_sec%60)))
        if [ "$eta_sec" -ge 3600 ]; then
             eta_formatted=$(printf "%02d:%02d:%02d" $((eta_sec/3600)) $(( (eta_sec%3600)/60 )) $((eta_sec%60)))
        fi
    else
        eta_formatted="--:--"
    fi
    
    # 進捗率
    percent=$(( count * 100 / total_files ))
    
    # ファイル名表示用に短縮（長すぎると表示崩れるため）
    filename=$(basename "$file")
    if [ ${#filename} -gt 20 ]; then
        disp_name="${filename:0:17}..."
    else
        disp_name="$filename"
    fi

    # --- 進捗表示 (キャリッジリターン \r で上書き) ---
    # \033[K はカーソル位置から行末まで削除するエスケープシーケンス
    printf "\r\033[K[ %d/%d ] %3d%% | ETA: %s | 処理中: %s" "$count" "$total_files" "$percent" "$eta_formatted" "$disp_name"
    
    # --- 画像処理 ---

    # 画像情報を取得 (幅 x 高さ)
    dimensions=$(identify -format "%w x %h" "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        # 読込エラー時は改行してからエラー表示し、再度進捗行を表示できるようにする
        printf "\r\033[K" 
        echo "[Skip] 読込不可: $file"
        continue
    fi
    
    # 幅と高さを数値として取得
    width=$(echo "$dimensions" | awk '{print $1}')
    height=$(echo "$dimensions" | awk '{print $3}')
    
    # 長辺を取得（iPad判定などで使用）
    if [ "$width" -gt "$height" ]; then
        long_side=$width
    else
        long_side=$height
    fi

    # アスペクト比計算 (width / height)
    aspect_ratio=$(echo "scale=3; $width / $height" | bc)
    
    # 16:9 フラグ (1.77 < ratio < 1.78)
    # パソコンのフォルダ分けでのみ使用
    is_16_9=0
    if (( $(echo "$aspect_ratio > 1.77" | bc -l) )) && (( $(echo "$aspect_ratio < 1.78" | bc -l) )); then
        is_16_9=1
    fi

    # --- 振り分けロジック ---
    
    dest_dir=""
    category=""
    is_lowres=0

    # 1. GearS3 (360x360 固定)
    if [ "$width" -eq 360 ] && [ "$height" -eq 360 ]; then
        dest_dir="$DEST_ROOT/GearS3"
        category="GearS3"
        count_gears3=$((count_gears3 + 1))

    # 2. スマホ (縦長 かつ アスペクト比 2.22周辺)
    elif [ "$height" -gt "$width" ] && \
         (( $(echo "scale=3; $height / $width > 2.21" | bc -l) )) && \
         (( $(echo "scale=3; $height / $width < 2.23" | bc -l) )); then
         
        # S22U基準: 高さ 3200px
        if [ "$height" -ge 3200 ]; then
            dest_dir="$DEST_ROOT/スマホ"
            category="スマホ"
            count_phone=$((count_phone + 1))
        else
            dest_dir="$DEST_ROOT/スマホ_S22U未満"
            category="スマホ(低)"
            count_lowres=$((count_lowres + 1))
        fi

    # 3. iPad Pro (アスペクト比 1.43周辺)
    elif (( $(echo "$aspect_ratio >= 1.42" | bc -l) && $(echo "$aspect_ratio <= 1.44" | bc -l) )) || \
         (( $(echo "$aspect_ratio >= 0.69" | bc -l) && $(echo "$aspect_ratio <= 0.70" | bc -l) )); then
         
        # 基準: 長辺 2388px
        if [ "$long_side" -ge 2388 ]; then
            dest_dir="$DEST_ROOT/iPad Pro"
            category="iPad Pro"
            count_ipad=$((count_ipad + 1))
        else
            dest_dir="$DEST_ROOT/iPad Pro_2388未満"
            category="iPad(低)"
            count_lowres=$((count_lowres + 1))
        fi

    # 4. パソコン (上記以外)
    else
        # 閾値設定 (16:9かどうかで判定基準が変わる)
        if [ "$is_16_9" -eq 1 ]; then
            th_4k=2160
            th_fhd=1080
        else
            th_4k=2400
            th_fhd=1200
        fi
        
        # 判定
        if [ "$height" -ge "$th_4k" ]; then
            # 4K以上
            dest_dir="$DEST_ROOT/パソコン"
            category="PC(4K)"
            count_pc=$((count_pc + 1))
        elif [ "$height" -ge "$th_fhd" ]; then
            # 4K未満 FHD以上
            dest_dir="$DEST_ROOT/パソコン_4K未満"
            if [ "$is_16_9" -eq 1 ]; then dest_dir="${dest_dir}-16_9"; fi
            category="PC(Mid)"
            count_pc=$((count_pc + 1))
        else
            # FHD未満
            dest_dir="$DEST_ROOT/パソコン_FHD未満"
            if [ "$is_16_9" -eq 1 ]; then dest_dir="${dest_dir}-16_9"; fi
            category="PC(Low)"
            count_lowres=$((count_lowres + 1))
        fi
    fi

    # --- 移動実行とログ出力 ---
    if [ -n "$dest_dir" ]; then
        mkdir -p "$dest_dir"
        mv "$file" "$dest_dir/"
        
        # ここで進捗行を一旦消去して、確定ログを表示する
        printf "\r\033[K"
        echo "[$category] $filename を移動しました"
    fi

done <<< "$files"

# 完了後の表示
printf "\r\033[K" # 最後の進捗行を消去
echo "----------------------------------------"
echo "処理完了。出力先: $DEST_ROOT"
echo "総ファイル数: $total_files"
echo "経過時間: $(printf "%02d:%02d" $((SECONDS/60)) $((SECONDS%60)))"
echo ""
echo "【内訳】"
echo "  GearS3 : $count_gears3"
echo "  スマホ : $count_phone"
echo "  iPad   : $count_ipad"
echo "  PC系   : $count_pc"
echo "  低画質 : $count_lowres (各未満フォルダへ移動済)"
echo "----------------------------------------"