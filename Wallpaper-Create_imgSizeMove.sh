#!/bin/bash

# ヘルプメッセージを表示する関数
show_help() {
  cat << EOF
Usage: $(basename "$0") <size | FHD | 4K | S22U>

指定された解像度の閾値未満の画像を、新しいフォルダに移動します。

Description:
  現在のディレクトリにある画像ファイル（jpg, png, jpeg）を分析し、
  指定された解像度よりも小さいものを移動させます。
  フォルダは現在のディレクトリの親に「<カレントディレクトリ名>_<閾値>未満」という名前で作成されます。
  アスペクト比が16:9の画像は、さらに「-16_9」という接尾辞が付いたフォルダに移動されます。

Arguments:
  size    移動対象とする画像の高さの最大値（ピクセル数）を指定します。
  FHD     FHD解像度（16:9の場合は高さ1080px、それ以外は1200px）を閾値とします。
  4K      4K解像度（16:9の場合は高さ2160px、それ以外は2400px）を閾値とします。
  S22U    Galaxy S22 Ultraの解像度（高さ3200px）を閾値とします。

Options:
  -h, --help    このヘルプメッセージを表示します。
EOF
}

# -h または --help が指定された場合、または引数がない場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [ -z "$1" ]; then
  show_help
  exit 0
fi

# 引数からサイズを取得
input=$1

# 処理フォルダ名を取得
current_dir=$(basename "$PWD")

# 親フォルダのパスを取得
parent_dir=$(dirname "$PWD")

# 移動先のフォルダを親フォルダに作成
target_dir="${parent_dir}/${current_dir}_${input}未満"
mkdir -p "$target_dir"

# 処理対象の画像ファイルをリストアップ
images=(*.jpg *.png *.jpeg)

# 総数を取得
total_files=${#images[@]}
echo "合計ファイル数は$total_files個です"

# カウンター初期化
count=0

# 解像度の高い方が閾値未満の画像を移動
for img in "${images[@]}"; do
  # ファイルが存在するか確認
  if [ ! -f "$img" ]; then
    echo "ファイルが存在しないのでスキップします : $img"
    echo "Progress: $count / $total_files"
    continue
  fi

  # 画像のサイズを取得
  width=$(identify -format "%w" "$img" 2>/dev/null)
  height=$(identify -format "%h" "$img" 2>/dev/null)

  # サイズが取得できない場合はスキップ
  if [ -z "$width" ] || [ -z "$height" ]; then
    echo "サイズが取得できないのでスキップします : $img"
    echo "Progress: $count / $total_files"
    continue
  fi

  # アスペクト比の計算
  aspect_ratio=$(echo "scale=2; $width / $height" | bc)
  is_16_9=$(echo "$aspect_ratio > 1.77 && $aspect_ratio < 1.78" | bc)

  # 16:9のフォルダを条件に応じて作成
  if [ "$is_16_9" -eq 1 ]; then
    target_dir_16_9="${target_dir}-16_9"
    mkdir -p "$target_dir_16_9"
  fi

  # サイズ条件の判断
  if [[ "$input" == "FHD" ]]; then
    if [ "$is_16_9" -eq 1 ]; then
      if [ "$height" -lt 1080 ]; then
        mv "$img" "$target_dir_16_9"
        echo "$img moved to ../$(basename "$target_dir_16_9")"
      else
        echo "$img はFHD条件に合致しないため移動されませんでした"
      fi
    else
      if [ "$height" -lt 1200 ]; then
        mv "$img" "$target_dir"
        echo "$img moved to ../$(basename "$target_dir")"
      else
        echo "$img はFHD条件に合致しないため移動されませんでした"
      fi
    fi
  elif [[ "$input" == "4K" ]]; then
    if [ "$is_16_9" -eq 1 ]; then
      if [ "$height" -lt 2160 ]; then
        mv "$img" "$target_dir_16_9"
        echo "$img moved to ../$(basename "$target_dir_16_9")"
      else
        echo "$img は4K条件に合致しないため移動されませんでした"
      fi
    else
      if [ "$height" -lt 2400 ]; then
        mv "$img" "$target_dir"
        echo "$img moved to ../$(basename "$target_dir")"
      else
        echo "$img は4K条件に合致しないため移動されませんでした"
      fi
    fi
  elif [[ "$input" == "S22U" ]]; then
    if [ "$height" -lt 3200 ]; then
      mv "$img" "$target_dir"
      echo "$img moved to ../$(basename "$target_dir")"
    else
      echo "$img はS22U条件に合致しないため移動されませんでした"
    fi
  else
    # サイズが指定されている場合の処理
    size_threshold=$input
    if [ "$height" -lt "$size_threshold" ]; then
      mv "$img" "$target_dir"
      echo "$img moved to ../$(basename "$target_dir")"
    else
      echo "$img は閾値以上のため移動されませんでした"
    fi
  fi

  count=$((count + 1))
  percent=$(echo "scale=2; $count * 100 / $total_files" | bc)
  echo "進捗: $count / $total_files ($percent%)"
done
