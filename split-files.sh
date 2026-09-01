#!/bin/bash

show_help() {
    cat << 'EOF'
使用方法:
    ./split-files.sh [オプション]

説明:
    カレントディレクトリ内のファイルを指定個数ごとに
    「カレントディレクトリ名-連番」という名前の子フォルダを作成して収納するのじゃ。
    引数を指定せずに実行した場合は、既定値（256個）で即座に処理を開始するぞ。

オプション:
    -n, --number 数値   1フォルダあたりの収納ファイル数を指定（規定値: 256）
    -h, --help          このヘルプを表示する
EOF
}

batch_size=256

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--number)
            if [ -n "$2" ] && [ "$2" -eq "$2" ] 2>/dev/null; then
                batch_size="$2"
                shift 2
            else
                echo "エラー: -n には数値を指定するのじゃ。"
                exit 1
            fi
            ;;
        *)
            echo "エラー: 未知のオプション '$1' じゃ。"
            show_help
            exit 1
            ;;
    esac
done

current_dir_name=$(basename "$PWD")
script_name=$(basename "$0")

# 対象ファイルの抽出（ディレクトリやスクリプト自身は除外）
files=()
for item in ./*; do
    if [ -f "$item" ]; then
        filename=$(basename "$item")
        if [ "$filename" != "$script_name" ]; then
            files+=("$item")
        fi
    fi
done

total_files=${#files[@]}

if [ "$total_files" -eq 0 ]; then
    echo "収納対象となるファイルが見つからなかったのじゃ。"
    exit 0
fi

echo "合計 ${total_files} 個のファイルを ${batch_size} 個ずつ収納するのじゃ。"

idx=1
for (( i=0; i<total_files; i+=batch_size )); do
    # 既存のフォルダ名が存在しなくなるまで連番をインクリメント
    while [ -e "${current_dir_name}-${idx}" ]; do
        idx=$((idx + 1))
    done

    target_dir="${current_dir_name}-${idx}"
    mkdir -p "$target_dir"

    # ファイルの移動
    for (( j=i; j<i+batch_size && j<total_files; j++ )); do
        mv -- "${files[j]}" "$target_dir/"
    done

    echo "フォルダ '${target_dir}' にファイルを収納したぞ。"
    idx=$((idx + 1))
done

echo "すべての収納が完了したのじゃ。"
