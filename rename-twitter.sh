#!/bin/sh
# 下にヘルプを実装してあるのじゃ

main() {
    OPT_SINGLE=false

    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                show_help
                exit 0
                ;;
            --adb|--single)
                OPT_SINGLE=true
                ;;
        esac
    done

    # ターゲットディレクトリを取得じゃ
    TARGET_DIR=""
    for arg in "$@"; do
        case "$arg" in
            -*) ;;
            *)
                TARGET_DIR="$arg"
                break
                ;;
        esac
    done

    if [ -z "$TARGET_DIR" ]; then
        show_help
        exit 0
    fi

    cd "$TARGET_DIR" || exit 1

    # '_' が含まれないファイルを先に「条件未満」へ移動するのじゃ
    mkdir -p "条件未満"
    for file in *; do
        [ -e "$file" ] || continue
        [ -f "$file" ] || continue
        prefix="${file%_*}"
        if [ "$prefix" = "$file" ]; then
            mv "$file" "条件未満/" 2>/dev/null
        fi
    done

    TMP_PREFIXES=$(mktemp)
    for file in *_*; do
        [ -e "$file" ] || continue
        [ -f "$file" ] || continue
        echo "${file%_*}"
    done | sort | uniq > "$TMP_PREFIXES"

    total=$(wc -l < "$TMP_PREFIXES")
    if [ "$total" -eq 0 ]; then
        echo "処理するプレフィックスが見つからんかったぞ。"
        rm -f "$TMP_PREFIXES"
        exit 0
    fi

    # adb shell等の環境判定じゃ
    if ! command -v nproc >/dev/null 2>&1; then
        OPT_SINGLE=true
    fi
    # Termux環境以外（UIDが10000未満）なら強制シングルスレッドじゃ
    if [ "$(id -u 2>/dev/null || echo 0)" -lt 10000 ]; then
        OPT_SINGLE=true
    fi

    TMP_LOG=$(mktemp)

    process_prefix() {
        local prefix="$1"
        
        if [ -d "$prefix" ]; then
            for match_file in "${prefix}"_*; do
                if [ -f "$match_file" ]; then
                    mv "$match_file" "$prefix/"
                fi
            done
            echo 1 >> "$TMP_LOG"
            return
        fi
        
        local count=0
        for match_file in "${prefix}"_*; do
            if [ -f "$match_file" ]; then
                count=$((count + 1))
            fi
        done
        
        if [ "$count" -ge 2 ]; then
            mkdir -p "$prefix"
            for match_file in "${prefix}"_*; do
                if [ -f "$match_file" ]; then
                    mv "$match_file" "$prefix/"
                fi
            done
        else
            for match_file in "${prefix}"_*; do
                if [ -f "$match_file" ]; then
                    mv "$match_file" "条件未満/"
                fi
            done
        fi
        
        echo 1 >> "$TMP_LOG"
    }

    if [ "$OPT_SINGLE" = "true" ]; then
        # シングルスレッド処理じゃ
        current=0
        while IFS= read -r prefix; do
            [ -z "$prefix" ] && continue
            current=$((current + 1))
            printf "\r\033[K[%d/%d] 直列処理中: %s" "$current" "$total" "$prefix"
            process_prefix "$prefix"
        done < "$TMP_PREFIXES"
    else
        # マルチスレッド処理じゃ
        MAX_JOBS=$(nproc 2>/dev/null || echo 4)
        [ "$MAX_JOBS" -gt 8 ] && MAX_JOBS=8

        monitor_progress() {
            while true; do
                local current=$(wc -l < "$TMP_LOG" 2>/dev/null || echo 0)
                printf "\r\033[K[%d/%d] 並列処理中..." "$current" "$total"
                if [ "$current" -ge "$total" ]; then
                    break
                fi
                sleep 0.5
            done
        }

        monitor_progress &
        MONITOR_PID=$!

        while IFS= read -r prefix; do
            [ -z "$prefix" ] && continue
            process_prefix "$prefix" &
            
            # wait -n が使えない環境のためのフォールバック処理じゃ
            while [ $(jobs -pr | wc -l) -ge $((MAX_JOBS + 1)) ]; do
                wait -n 2>/dev/null || sleep 0.1
            done
        done < "$TMP_PREFIXES"

        wait
        kill $MONITOR_PID 2>/dev/null
    fi

    rm -f "$TMP_PREFIXES" "$TMP_LOG"

    echo ""
    echo "完了したぞ！"
}

show_help() {
    echo "Usage: $0 [オプション] <target_directory>"
    echo "  <target_directory> : 対象ディレクトリ"
    echo "  -h, --help         : ヘルプを表示するのじゃ"
    echo "  --adb, --single    : ADB shell等の環境向けに直列（シングル）で処理するのじゃ"
}

main "$@"