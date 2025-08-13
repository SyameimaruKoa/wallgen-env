#!/bin/bash
# UTF-8で保存するのじゃぞ

# --- 使い方 ---
# ./script.name [解像度] [元拡張子] {オプション1} {オプション2}
#
# [解像度]    : 必須。リサイズ後の基準となる解像度 (例: 2400)
# [元拡張子]  : 必須。変換したい画像の拡張子 (例: png)
# {オプション}: 任意。"fit" または "webp" を指定できる。順不同。
#   - fit  : 画像全体が指定解像度に収まるようにリサイズする（長辺基準）。
#            指定しない場合は、画像の縦の長さを基準にリサイズする。
#   - webp : 出力形式をWebPにする。指定しない場合はJPGになる。
# ----------------

# --- 必須引数のチェック ---
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "引数が足りんぞ！"
  echo "使い方: $0 [解像度] [元拡張子] {fit} {webp}"
  echo "例 (縦2400pxのJPGに): $0 2400 png"
  echo "例 (長辺2400pxのJPGに): $0 2400 heic fit"
  echo "例 (長辺2400pxのWebPに): $0 2400 jpg fit webp"
  exit 1
fi

# --- 引数の受け取りと設定 ---
max_size=$1
source_ext=$2
# デフォルト値を設定
resize_mode="portrait" # portrait: 縦基準, fit: 長辺基準
output_format="jpg"    # jpg または webp

# 3番目以降の引数を解析して、オプションを設定
for arg in "${@:3}"; do
  case $arg in
    fit)
      resize_mode="fit"
      ;;
    webp)
      output_format="webp"
      ;;
  esac
done

# --- 実行処理 ---
# 出力フォルダ名を決める
dir_name=$(basename "$PWD")
output_folder="./${dir_name}_Resized_${max_size}px"

# 出力フォルダがなければ作成する
mkdir -p "$output_folder"

# 変換対象のファイルリストを作成する
source_files=("./"*.${source_ext})
total_files=${#source_files[@]}

# 対象ファイルが一つもなければ終了する
if [ $total_files -eq 0 ]; then
  echo "拡張子 '${source_ext}' のファイルが見つからんかったぞ。"
  exit 1
fi

# ImageMagickのコマンドを確認する
if command -v magick >/dev/null 2>&1; then
  CMD="magick"
elif command -v convert >/dev/null 2>&1; then
  CMD="convert"
else
  echo "エラー: このスクリプトの実行には ImageMagick が必要じゃ。" >&2
  exit 1
fi

echo "--- 変換を開始する ---"
echo "入力元: カレントディレクトリの *.${source_ext} ファイル"
echo "出力先: ${output_folder}"
echo "リサイズモード: ${resize_mode}"
echo "出力形式: ${output_format}"
echo "----------------------"

# ファイルを一つずつ処理するループ
count=0
for img_path in "${source_files[@]}"; do
  # 拡張子を除いたファイル名を取得
  filename_no_ext=$(basename "$img_path" ".${source_ext}")

  # リサイズモードによってImageMagickのオプションを切り替える
  if [ "$resize_mode" == "fit" ]; then
    # 画像全体が[size]x[size]の四角に収まるようにリサイズ
    resize_option="${max_size}x${max_size}>"
  else
    # 画像の縦の長さが[size]になるようにリサイズ
    resize_option="x${max_size}"
  fi

  # 出力用のファイルパスを組み立てる
  output_path="${output_folder}/${filename_no_ext}.${output_format}"

  # 画像をリサイズして変換・保存する
  $CMD "$img_path" -resize "$resize_option" -quality 90 "$output_path"

  # 進捗を表示する
  count=$((count + 1))
  progress=$(echo "scale=2; $count * 100 / $total_files" | bc)
  echo "[${count}/${total_files}] ${progress}% 完了: ${output_path}"
done

echo "----------------------"
echo "全てのファイルの変換が完了したぞ！"