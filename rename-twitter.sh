#!/bin/sh
# 下にヘルプを実装してあるのじゃ

main() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
        show_help
        exit 0
    fi
    cd "$1" || exit 1

    total=0
    for i in *; do
        [ -e "$i" ] || continue
        total=$((total + 1))
    done

    if [ "$total" -eq 0 ]; then
        echo "処理するファイルが見つからんかったぞ。"
        exit 0
    fi

    current=0
    for file in *; do
        [ -e "$file" ] || continue
        current=$((current + 1))
        
        # 進捗を同じ行に上書き表示するのじゃ
        printf "\r\033[K[%d/%d] 処理中: %s" "$current" "$total" "$file"
        
        [ -f "$file" ] || continue
        prefix="${file%_*}"
        if [ "$prefix" = "$file" ]; then
            continue
        fi
        
        if [ -d "$prefix" ]; then
            for match_file in "${prefix}"_*; do
                if [ -f "$match_file" ]; then
                    mv "$match_file" "$prefix/"
                fi
            done
            continue
        fi
        
        count=0
        for match_file in "${prefix}"_*; do
            if [ -f "$match_file" ]; then
                count=$((count + 1))
            fi
        done
        
        if [ "$count" -ge 3 ]; then
            mkdir -p "$prefix"
            for match_file in "${prefix}"_*; do
                if [ -f "$match_file" ]; then
                    mv "$match_file" "$prefix/"
                fi
            done
        fi
    done
    
    # 最後に改行を入れて表示を整えるのじゃ
    echo ""
    echo "完了したぞ！"
}

show_help() {
    echo "Usage: $0 <target_directory>"
    echo "  <target_directory> : 対象ディレクトリ"
    echo "  -h, --help         : ヘルプ"
}

main "$@"
