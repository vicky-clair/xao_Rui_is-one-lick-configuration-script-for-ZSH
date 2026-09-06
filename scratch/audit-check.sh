#!/usr/bin/env bash
# 隔离审计：只替换更新检查子脚本，不运行安装/联网/提权。
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d "$root/scratch/audit-XXXXXXXX")
mkdir -p "$stage/scripts"
cp "$root/install.sh" "$stage/install.sh"
printf '#!/usr/bin/env bash\nprintf "called\\n" > "$AUDIT_MARKER"\n' > "$stage/scripts/check_updates.sh"
export AUDIT_MARKER="$stage/update-check-ran"
bash -n "$root/install.sh"
bash -n "$root/scripts/check_updates.sh"
bash "$stage/install.sh" --dry-run --check-updates --lang en
if [[ -f "$AUDIT_MARKER" ]]; then
  printf 'REPRODUCED: --dry-run --check-updates executed the mutation-capable update checker\n'
fi
printf 'Evidence directory: %s\n' "$stage"
