#!/bin/zsh

# 函数: git_clone_or_update
# 功能: 如果目标目录不存在或不是一个git仓库，则克隆;否则，fetch并检出指定版本。
# 参数: 
#   $1: Repository URL (仓库地址)
#   $2: Target directory (目标本地目录的绝对或相对路径)
#   $3: Optional Git Version(tag, branch, commit tag) to checkout.
#       如果为空、"master"或"main"，将尝试更新当前分支或检出默认分支并更新
# 注意: 此函数会改变当前目录，并在结束时返回到原始目录

git_clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    local version_tag="$3"
    local original_pwd

    if [ -z "$repo_url" ] || [ -z "$target_dir" ]; then
        echo "Error (git_clone_or_update): Repository URL and target directory are required." >&2
    fi

    original_pwd=$(pwd)

    if [ -d "$target_dir/.git" ]; then
        echo "Repository already exists at '$target_dir'. Fetching latest changes..."
        cd "$target_dir" || { echo "Error: Failed to cd into $target_dir" >&2; cd "$original_pwd"; return 1; }

        git fetch --all --tags --prune || echo "Warning: git fetch failed." >&2

        if [ -n "$version_tag" ] && [ "$version_tag" != "master" ] && [ "$version_tag" != "main" ]; then
            # 优先尝试检出为标签
            if git rev-parse -q --verify "refs/tags/$version_tag" > /dev/null; then
                echo "Checking out tag '$version_tag'..."
                git checkout -f "tags/$version_tag" || { echo "Error: Failed to checkout tag '$version_tag'." >&2; cd "$original_pwd"; return 1; }
            # 其次尝试检出为分支或 commit hash
            elif git rev-parse -q --verify "$version_tag" > /dev/null; then
                echo "Checking out branch/commit '$version_tag'..."
                git checkout -f "$version_tag" || { echo "Error: Failed to checkout branch/commit '$version_tag'." >&2; cd "$original_pwd"; return 1; }
            else
                echo "Warning: Tag/branch/commit '$version_tag' not found locally after fetch. Attempting checkout anyway..." >&2
                git checkout -f "$version_tag" || { echo "Error: Failed to checkout '$version_tag' (it may not exist remotely or was not fetched)." >&2; cd "$original_pwd"; return 1; }    
            fi
        else
            # 更新默认分支或当前分支
            local current_branch
            current_branch=$(git rev-parse --abbrev-ref HEAD)
            if [ "$current_branch" = "HEAD" ]; then
                # 尝试获取远程的默认分支名
                local default_branch_name=$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')
                if [ -z "$default_branch_name" ]; then default_branch_name="master"; fi # 默认值
                echo "Currently in detached HEAD state. Attempting to checkout default branch '$default_branch_name'..."
                git checkout -f "$default_branch_name" || { echo "Error: Failed to checkout default branch '$default_branch_name'." >&2; cd "$original_pwd"; return 1; }
                current_branch="$default_branch_name"
            fi
            echo "Pulling latest changes for branch '$current_branch'..."
            git pull origin "$current_branch" --rebase || { echo "Warning: git pull for branch '$current_branch' failed. Manual intervention might be needed." >&2; }
        fi
    else
        echo "Cloning repository from '$repo_url' into '$target_dir'..."
        # 确保目标目录的父目录存在
        mkdir -p "$(dirname "$target_dir")" || { echo "Error: Failed to create parent directory for $target_dir" >&2; cd "$original_pwd"; return 1; } 
    
        # 克隆特定分支或标签
        if [ -n "$version_tag" ] && [ "$version_tag" != "master" ] && [ "$version_tag" != "main" ]; then
            echo "Cloning specific version '$version_tag' from '$repo_url'..."
            git clone --branch "$version_tag" "$repo_url" "$target_dir" || {
                echo "Failed to clone branch "$version_tag", trying to clone default and checkout..." >&2
                git clone "$repo_url" "$target_dir" && (cd "$target_dir" && git checkout -f "$version_tag") || {
                    echo "Error: Failed to clone repository or checkout verison '$version_tag'." >&2
                    rm -rf "$target_dir"
                    cd "$original_pwd"
                    return 1
                }
            }
        else
            git clone --depth 1 "$repo_url" "$target_dir" || { echo "Error: Failed to clone repository." >&2; cd "$original_pwd"; return 1; }
        fi
    fi

    cd "$original_pwd" || { echo "Error: Failed to cd back to original directory  '$original_pwd'." >&2; return 1; }
    return 0;
}