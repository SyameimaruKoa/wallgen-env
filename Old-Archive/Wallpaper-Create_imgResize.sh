#!/bin/bash
# UTF-8で保存するのじゃぞ

# ヘルプメッセージを表示する関数
show_help() {
  cat << EOF
Usage: $(basename "$0") <resolution> <source_ext> [fit] [webp]

指定した拡張子の画像をリサイズし、JPGまたはWebP形式で保存します。

Description:
  カレントディレクトリにある指定された拡張子の画像ファイルを、指定の解像度に
  リサイズします。出力先として「<カレントディレクトリ名>_Resized_<解像度>px」
  という名前のフォルダが自動的に作成されます。

Arguments:
  resolution   必須。リサイズ後の基準となる解像度（ピクセル数）を指定します。
               例: 2400
  source_ext   必須。変換したい画像の拡張子を指定します。
               例: png

Options:
  fit           任意。このオプションを指定すると、画像の長辺が<resolution>に
                収まるようにリサイズされます（アスペクト比は維持）。
                指定しない場合は、画像の高さが<resolution>になるようにリサイズされます。
  webp          任意。このオプションを指定すると、出力形式がWebPになります。
                指定しない場合はJPG形式で保存されます。
  -h, --help    このヘルプメッセージを表示します。

Examples:
  # PNG画像を高さ2400pxのJPGに変換
  $(basename "$0") 2400 png

  # HEIC画像を長辺2400pxのJPGに変換
  $(basename "$0") 2400 heic fit

  # JPG画像を長辺2400pxのWebPに変換
  $(basename "$0") 2400 jpg fit webp
EOF
}

# -h または --help が指定された場合、または必須引数が2つ未満の場合にヘルプを表示
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] || [ $# -lt 2 ]; then
  show_help
  exit 0
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
if [ ${#source_files[@]} -eq 0 ] || [ ! -f "${source_files[0]}" ]; then
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
