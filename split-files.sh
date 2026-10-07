#!/bin/bash

show_help() {
    cat << 'EOF'
使用方法:
    ./split-files.sh [オプション] [フォルダ ...]

説明:
    カレントディレクトリ内のファイルを指定個数ごとに
    「カレントディレクトリ名-連番」という名前の子フォルダを作成して収納するのじゃ。
    フォルダ省略時は「.」と同じくカレントディレクトリを処理するぞ。
    複数フォルダやワイルドカード（例: ./split-files.sh "画像*"）も指定できるぞ。

オプション:
    -n, --number 数値   1フォルダあたりの収納ファイル数を指定（規定値: 256）
    -h, --help          このヘルプを表示する
EOF
}

batch_size=256
directory_patterns=()

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--number)
            if [[ ${2:-} =~ ^[0-9]+$ ]] && [ "$2" -gt 0 ] 2>/dev/null; then
                batch_size=$((10#$2))
                shift 2
            else
                echo "エラー: -n には正の整数を指定するのじゃ。"
                exit 1
            fi
            ;;
        --)
            shift
            directory_patterns+=("$@")
            break
            ;;
        -*)
            echo "エラー: 未知のオプション '$1' じゃ。"
            show_help
            exit 1
            ;;
        *)
            directory_patterns+=("$1")
            shift
            ;;
    esac
done

# 移動を始める前に、すべての指定を展開・検証する。
if [ ${#directory_patterns[@]} -eq 0 ]; then
    directory_patterns=(.)
fi
shopt -s nullglob
directories=()
expand_directories() {
    local pattern="$1" item resolved existing duplicate found=0
    local IFS=''
    local matches=()
    if [ -d "$pattern" ]; then
        matches=("$pattern")
    else
        # 単語分割を無効にし、空白を含むパスでもワイルドカードだけを展開する。
        matches=( $pattern )
    fi
    for item in "${matches[@]}"; do
        [ -d "$item" ] || continue
        found=1
        resolved=$(cd -- "$item" && pwd -P) || return 1
        duplicate=0
        for existing in "${directories[@]}"; do
            [ "$existing" != "$resolved" ] || duplicate=1
        done
        [ "$duplicate" -eq 1 ] || directories+=("$resolved")
    done
    if [ "$found" -eq 0 ]; then
        echo "エラー: フォルダ '$pattern' が見つからないのじゃ。" >&2
        return 1
    fi
}
for pattern in "${directory_patterns[@]}"; do
    expand_directories "$pattern" || exit 1
done

script_name=$(basename "$0")
split_directory() (
    cd -- "$1" || exit 1
    current_dir_name=$(basename "$PWD")

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
        mkdir -- "$target_dir" || exit 1

        # ファイルの移動
        for (( j=i; j<i+batch_size && j<total_files; j++ )); do
            mv -- "${files[j]}" "$target_dir/" || exit 1
        done

        echo "フォルダ '${target_dir}' にファイルを収納したぞ。"
        idx=$((idx + 1))
    done

    echo "すべての収納が完了したのじゃ。"
)

for directory in "${directories[@]}"; do
    echo "対象フォルダ: $directory"
    split_directory "$directory" || exit 1
done
