#!/bin/sh
# clean-empty-dirs.sh
# イラスト編集用フォルダ内の不要な空フォルダを再帰的に削除し、
# 未整理フォルダ内の単一の入れ子フォルダを解消する。

set -eu

# ヘルプ表示
show_help() {
    cat <<EOF
使い方:
  sh clean-empty-dirs.sh [オプション] [ターゲットフォルダ]

説明:
  setup-illust-env.sh で作成されるテンプレートフォルダ構造を維持しつつ、
  それ以外の空フォルダを再帰的に削除します。
  また、未整理/ 配下において、フォルダが1つのみで入れ子になっている場合は入れ子を解消します。

オプション:
  -d, --dry-run   実際には削除・移動せず、シミュレーション結果を表示します
  -h, --help      このヘルプを表示して終了します

実行例:
  # ドライラン実行（確認のみ）
  sh clean-empty-dirs.sh --dry-run /path/to/illust-dir

  # 実際に処理を実行
  sh clean-empty-dirs.sh /path/to/illust-dir
EOF
}

# オプション解析
OPT_DRY_RUN=false
TARGET_DIR=""

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            OPT_DRY_RUN=true
            ;;
        *)
            if [ -z "$TARGET_DIR" ]; then
                TARGET_DIR="$arg"
            else
                echo "[ERROR] 引数が多すぎます: '$arg'" >&2
                show_help
                exit 1
            fi
            ;;
    esac
done

# ターゲットフォルダが指定されていない場合はカレントディレクトリを使用
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="."
fi

# ターゲットフォルダの存在確認と絶対パスの取得
if [ ! -d "$TARGET_DIR" ]; then
    echo "[ERROR] 指定されたターゲットディレクトリが存在しません: $TARGET_DIR" >&2
    exit 1
fi

TARGET_DIR_ABS=$(cd "$TARGET_DIR" && pwd)

# 安全のためのチェック (整理済み, 未整理 フォルダの存在確認)
if [ ! -d "$TARGET_DIR_ABS/整理済み" ] || [ ! -d "$TARGET_DIR_ABS/未整理" ]; then
    echo "[ERROR] 指定されたディレクトリはイラスト編集用フォルダではない可能性があります。" >&2
    echo "        (整理済み/ および 未整理/ フォルダが見つかりません)" >&2
    exit 1
fi

echo "[INFO]  イラスト編集用フォルダを検出しました: $TARGET_DIR_ABS"
if [ "$OPT_DRY_RUN" = "true" ]; then
    echo "[INFO]  === DRY RUN モード（実際には変更しません） ==="
fi

# テンプレートフォルダであるかの判定関数
is_protected() {
    local rel_path="$1"
    case "$rel_path" in
        .) return 0 ;;
        "Photo Editor") return 0 ;;
        "Script"|"Script"/*) return 0 ;;
        "壁紙転送") return 0 ;;
        "整理済み") return 0 ;;
        "整理済み/イラスト") return 0 ;;
        "整理済み/裏イラスト") return 0 ;;
        "整理済み/公式") return 0 ;;
        "整理済み/移動用") return 0 ;;
        "整理済み/素材") return 0 ;;
        "未整理") return 0 ;;
        "未整理/Twitter") return 0 ;;
        "未整理/pixiv") return 0 ;;
        *) return 1 ;;
    esac
}

# 1つだけフォルダが入っていて、他にファイルが存在しないか判定する関数
# 条件を満たす場合は、その中のフォルダパスを返し、ステータスコード0を返す。
get_single_subdir() {
    local dir="$1"
    
    # ファイル・フォルダの一覧数をカウント (ls -A を利用)
    local entry_count
    entry_count=$(ls -A "$dir" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$entry_count" -ne 1 ]; then
        return 1
    fi
    
    local entry_name
    entry_name=$(ls -A "$dir" 2>/dev/null)
    if [ -d "$dir/$entry_name" ]; then
        echo "$dir/$entry_name"
        return 0
    fi
    return 1
}

# 処理カウンター
deleted_count=0

# TARGET_DIR に移動して処理を行うことで相対パスのハンドリングを容易にする
cd "$TARGET_DIR_ABS"

# find -depth で深い階層のディレクトリから順にリストアップ
# POSIX sh 互換のためテンポラリファイルを使用してループを回す
tmp_dirs=".dirs_$$"
find . -depth -type d > "$tmp_dirs"

while read -r dir; do
    # ./ を除去して相対パスを取得
    rel_path="${dir#./}"
    
    # テンプレートフォルダはスキップ
    if is_protected "$rel_path"; then
        continue
    fi
    
    # ディレクトリが存在するか確認 (途中で親フォルダが削除された場合への対策)
    if [ ! -d "$rel_path" ]; then
        continue
    fi
    
    # 1. 空であるか判定して削除
    if [ -z "$(ls -A "$rel_path" 2>/dev/null)" ]; then
        if [ "$OPT_DRY_RUN" = "true" ]; then
            echo "[DRY] 削除予定: $rel_path"
            deleted_count=$((deleted_count + 1))
        else
            if rmdir "$rel_path" 2>/dev/null; then
                echo "[OK]    削除しました: $rel_path"
                deleted_count=$((deleted_count + 1))
            else
                echo "[WARN]  削除失敗: $rel_path" >&2
            fi
        fi
        continue
    fi
    
    # 2. 未整理/ 配下の場合のみ、単一の入れ子（中にフォルダが1つだけ）を解消する
    case "$rel_path" in
        未整理/*)
            if single_sub=$(get_single_subdir "$rel_path"); then
                parent_dir=$(dirname "$rel_path")
                subdir_name=$(basename "$single_sub")
                target_dest="$parent_dir/$subdir_name"
                
                if [ -e "$target_dest" ]; then
                    echo "[WARN]  移動先に同名フォルダが存在するため入れ子解消をスキップします: $target_dest" >&2
                else
                    if [ "$OPT_DRY_RUN" = "true" ]; then
                        echo "[DRY] 入れ子解消: $single_sub を $parent_dir に移動し、空になった $rel_path を削除"
                        deleted_count=$((deleted_count + 1))
                    else
                        # フォルダを親階層に移動
                        if mv "$single_sub" "$parent_dir/"; then
                            # 空になった親フォルダを削除
                            if rmdir "$rel_path" 2>/dev/null; then
                                echo "[OK]    入れ子解消しました: $single_sub を $parent_dir に移動し、$rel_path を削除しました"
                                deleted_count=$((deleted_count + 1))
                            else
                                echo "[WARN]  入れ子解消後の親フォルダ削除に失敗しました: $rel_path" >&2
                            fi
                        else
                            echo "[WARN]  フォルダの移動に失敗しました: $single_sub -> $parent_dir/" >&2
                        fi
                    fi
                fi
            fi
            ;;
    esac
done < "$tmp_dirs"

# テンポラリファイルの削除
rm -f "$tmp_dirs"

echo "[INFO]  処理完了: 削除したフォルダ数=${deleted_count}件"
