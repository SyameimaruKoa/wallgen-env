#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
  cat << EOF
Usage: $(basename "$0")

カレントディレクトリ内の画像ファイルを、解像度やアスペクト比に応じて
デバイス別のフォルダに自動で振り分けます。

Description:
  このスクリプトは、カレントディレクトリにある画像ファイル（jpg, jpeg, png, webp）を
  分析し、以下のルールに基づいて「壁紙転送」フォルダ内の各デバイス用サブフォルダに移動します。
  - GearS3     : 360x360pxの画像
  - スマホ       : 縦長で特定のアスペクト比（約2.22）の画像
  - iPad Pro   : 特定のアスペクト比（約1.43）の画像
  - パソコン     : 上記のいずれにも一致しない画像

Prerequisites:
  このスクリプトを実行するには 'bc' と 'ImageMagick' が必要です。

Options:
  -h, --help    このヘルプメッセージを表示します。
EOF
}

# -h または --help が指定された場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  show_help
  exit 0
fi

# bc と ImageMagick のインストール確認
command -v bc >/dev/null 2>&1 || {
    echo "Error: 'bc' is not installed. Please install it using 'pkg install bc'."
    exit 1
}
command -v identify >/dev/null 2>&1 || {
    echo "Error: 'ImageMagick' (identify) is not installed. Please install it using 'pkg install imagemagick'."
    exit 1
}

# スクリプト自身のディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 移動先フォルダを設定
GEARS3_DIR="$SCRIPT_DIR/壁紙転送/GearS3"
SMARTPHONE_DIR="$SCRIPT_DIR/壁紙転送/スマホ"
IPAD_DIR="$SCRIPT_DIR/壁紙転送/iPad Pro"
PC_DIR="$SCRIPT_DIR/壁紙転送/パソコン"

# 移動先フォルダ作成
mkdir -p "$GEARS3_DIR" "$SMARTPHONE_DIR" "$IPAD_DIR" "$PC_DIR"

# カレントディレクトリ内の対象画像ファイルをリスト化
files=$(find . -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \))

# ファイル数を取得
total_files=$(echo "$files" | wc -l)
processed_files=0
gears3_files=0
smartphone_files=0
ipad_files=0
pc_files=0

if [ "$total_files" -eq 0 ]; then
    echo "対象ファイルが見つかりませんでした。"
    exit 0
fi

echo "処理を開始します。全ファイル数: $total_files"

# ファイルを1つずつ処理 (ヒア文字列を使用)
while read -r file; do
    processed_files=$((processed_files + 1))

    if [ ! -f "$file" ]; then
        echo "ファイルが見つかりません: $file"
        continue
    fi

    # 画像サイズを取得
    dimensions=$(identify -format "%wx%h" "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "画像サイズの取得に失敗: $file"
        continue
    fi

    # 幅と高さを抽出
    width=$(echo "$dimensions" | cut -d'x' -f1)
    height=$(echo "$dimensions" | cut -d'x' -f2)

    original_width=$width
    original_height=$height

    is_portrait=false
    if [ "$width" -lt "$height" ]; then
        is_portrait=true
        width=$original_height
        height=$original_width
    fi

    # アスペクト比の計算 (精度3)
    aspect_ratio=$(echo "scale=3; $width / $height" | bc)

    moved=false

    if [ "$dimensions" = "360x360" ]; then
        mv "$file" "$GEARS3_DIR"
        echo "GearS3へ移動: $file"
        gears3_files=$((gears3_files + 1))
        moved=true
    fi

    if $is_portrait && (($(echo "$aspect_ratio > 2.21" | bc -l))) && (($(echo "$aspect_ratio < 2.23" | bc -l))); then
        mv "$file" "$SMARTPHONE_DIR"
        echo "スマホへ移動: $file"
        smartphone_files=$((smartphone_files + 1))
        moved=true
    fi

    ipad_ratio=$(echo "scale=3; 199 / 139" | bc)
    lower_bound=$(echo "scale=3; $ipad_ratio - 0.01" | bc)
    upper_bound=$(echo "scale=3; $ipad_ratio + 0.01" | bc)

    if (($(echo "$aspect_ratio >= $lower_bound" | bc -l))) && (($(echo "$aspect_ratio <= $upper_bound" | bc -l))); then
        mv "$file" "$IPAD_DIR"
        echo "iPadへ移動: $file"
        ipad_files=$((ipad_files + 1))
        moved=true
    fi

    if ! $moved; then
        mv "$file" "$PC_DIR"
        echo "パソコンへ移動: $file"
        pc_files=$((pc_files + 1))
        moved=true
    fi

    echo "総合進捗: $processed_files/$total_files ($(($processed_files * 100 / $total_files))%) - GearS3: $gears3_files - スマホ: $smartphone_files - iPad: $ipad_files - PC: $pc_files"

done <<<"$files"

echo -e "\n処理が完了しました。"
echo "総合ファイル数: $total_files"
echo "GearS3用ファイル数: $gears3_files"
echo "スマホ用ファイル数: $smartphone_files"
echo "iPad Pro用ファイル数: $ipad_files"
echo "パソコン用ファイル数: $pc_files"

exit 0
