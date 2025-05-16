#!/bin/bash

# 解像度を引数で指定する
max_size=$1
resize_mode=$2

# max_sizeが指定されていない場合はエラーを表示して終了する
if [ -z "$max_size" ]; then
  echo "リサイズする最大解像度を指定しておくれ。例: ./script.sh 2388 [iPad]"
  exit 1
fi

# 現在のディレクトリ名を取得して、その後ろに"_webp"または"_jpg"をつけたフォルダ名にする
dir_name=$(basename "$PWD")
if [ "$resize_mode" == "iPad" ]; then
  output_folder="./${dir_name}_webp"
else
  output_folder="./${dir_name}_jpg"
fi

# 出力フォルダが存在しない場合は作成する
mkdir -p "$output_folder"

# フォルダ内のPNG画像を取得
png_files=("./"*.png)
total_files=${#png_files[@]}

# PNGファイルが見つからない場合は終了
if [ $total_files -eq 0 ]; then
  echo "PNGファイルが見つからんぞ。"
  exit 1
fi

# リサイズオプションを決定
if [ "$resize_mode" == "iPad" ]; then
  resize_option="${max_size}x${max_size}>"
else
  resize_option="x${max_size}"
fi

# ファイルを処理し、進捗を表示する
count=0
for img in "${png_files[@]}"; do
  # ファイル名を取得
  filename=$(basename "$img" .png)

  # コマンドの存在確認
  if command -v magick >/dev/null 2>&1; then
    CMD="magick"
  elif command -v convert >/dev/null 2>&1; then
    CMD="convert"
  else
    echo "エラー: 「magick」も「convert」もインストールされていません。" >&2
    exit 1
  fi

  # 実行
  if [ "$resize_mode" == "iPad" ]; then
    $CMD "$img" -resize "$resize_option" -quality 95 "${output_folder}/${filename}.webp"
  else
    $CMD "$img" -resize "$resize_option" -quality 95 "${output_folder}/${filename}.jpg"
  fi

  # 進捗を表示
  count=$((count + 1))
  progress=$(echo "scale=2; $count * 100 / $total_files" | bc)
  echo "[$count/$total_files] 進捗: ${progress}%"
done

echo "全ファイルの変換が完了したぞ！"
