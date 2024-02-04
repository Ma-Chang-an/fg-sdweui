#!/bin/bash

set -Eeuox pipefail

NAS_DIR="/mnt/auto/sd"

function mount_file() {
  echo Mount $1 to $2

  SRC="$1"
  DST="$2"

  rm -rf "${DST}"

  if [ ! -f "${SRC}" ]; then
    mkdir -pv "${SRC}"
  fi

  mkdir -pv "$(dirname "${DST}")"

  ln -sT "${SRC}" "${DST}"
}

function mount_pro() {
  mkdir -p "${NAS_DIR}"

  # 去除无用的软链接
  find -L . -type l -delete

  echo "with NAS, mount built-in files to ${NAS_DIR}"

  find ${SD_BUILTIN} | while read -r file; do
    SRC="${file}"
    DST="${NAS_DIR}/${file#$SD_BUILTIN/}"

    if [ ! -e "$DST" ] && [ ! -d "$SRC" ] && [ "$DST" != "${NAS_DIR}/config.json" ] && [ "$DST" != "${NAS_DIR}/ui-config.json" ]; then
      mount_file "$SRC" "$DST"
    fi
  done

  if [ ! -e "${NAS_DIR}/config.json" ]; then
    echo "no config.json, copy it"
    cp "${SD_BUILTIN}/config.json" "${NAS_DIR}/config.json"
  fi

  if [ "$(wc -c ${NAS_DIR}/config.json | cut -f 1 -d ' ')" == "0" ]; then
    echo "config.json is empty, copy it"
    rm -f "${SD_BUILTIN}/config.json"
    cp "${SD_BUILTIN}/config.json" "${NAS_DIR}/config.json"
  fi

  if [ ! -e "${NAS_DIR}/ui-config.json" ]; then
    echo "no ui-config.json, copy it"
    cp "${SD_BUILTIN}/ui-config.json" "${NAS_DIR}/ui-config.json"
  fi
}

count=0
while [ $count -lt 25 ]
do
    if [ -d "/mnt/auto" ]
    then
        echo "Directory /mnt/auto exists. Begin Mount."
        #mount_pro
	      break
    else
        echo "Directory /mnt/auto does not exist. Waiting for 1 seconds."
        sleep 1
        count=$((count+1))
    fi
done
if [ $count -ge 15 ]; then
  echo "Directory /mnt/auto does not exist. Maximum wait time exceeded."
  #mount_file "$SD_BUILTIN" "${NAS_DIR}"
fi

mount_pro

if [ ! -e "${NAS_DIR}/styles.csv" ]; then
  echo "no styles.csv, create it"
  touch "${NAS_DIR}/styles.csv"
fi
declare -A MOUNTS

# 遍历/mnt/auto/sd/root目录下的所有子目录和文件
for file in ${NAS_DIR}/root/{*,.*}; do
    if [ "$(basename "$file")" != "." ] && [ "$(basename "$file")" != ".." ] && [ "$(basename "$file")" != "*" ]; then
        echo $(basename "$file");
        MOUNTS["${HOME}/$(basename "$file")"]="$file"	
    fi;
done
#MOUNTS["/root"]="${NAS_DIR}/root"
MOUNTS["${ROOT}/models"]="${NAS_DIR}/models"
MOUNTS["${ROOT}/localizations"]="${NAS_DIR}/localizations"
MOUNTS["${ROOT}/configs"]="${NAS_DIR}/configs"
MOUNTS["${ROOT}/extensions-builtin"]="${NAS_DIR}/extensions-builtin"
MOUNTS["${ROOT}/embeddings"]="${NAS_DIR}/embeddings"
MOUNTS["${ROOT}/config.json"]="${NAS_DIR}/config.json"
MOUNTS["${ROOT}/ui-config.json"]="${NAS_DIR}/ui-config.json"
MOUNTS["${ROOT}/extensions"]="${NAS_DIR}/extensions"
MOUNTS["${ROOT}/outputs"]="${NAS_DIR}/outputs"
MOUNTS["${ROOT}/styles.csv"]="${NAS_DIR}/styles.csv"
MOUNTS["${ROOT}/scripts"]="${NAS_DIR}/scripts"
MOUNTS["${ROOT}/textual_inversion_templates"]="${NAS_DIR}/textual_inversion_templates"
MOUNTS["${ROOT}/repositories/CodeFormer/weights/facelib"]="${NAS_DIR}/repositories/CodeFormer/weights/facelib"


for to_path in "${!MOUNTS[@]}"; do
  mount_file "${MOUNTS[${to_path}]}" "${to_path}"
done

CLI_ARGS="${CLI_ARGS:---xformers --enable-insecure-extension-access --skip-version-check --no-download-sd-model --skip-prepare-environment --no-gradio-queue}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
AD_NO_HUGGINGFACE=""

# 如果插件目录中包含adetailer
if [ -d "${ROOT}/extensions/adetailer" ];then
  if [ -f ${ROOT}/config.json ]; then
    # 读取JSON文件
    json=$(cat ${ROOT}/config.json)
    # 使用jq检查"disabled_extensions"数组中是否存在"adetailer"
    if echo "$json" | jq -e '.disabled_extensions[] | select(.=="adetailer")' > /dev/null; then
      echo "'adetailer' in 'disabled_extensions'"
    else
      echo "'adetailer' not in 'disabled_extensions'"
      AD_NO_HUGGINGFACE="--ad-no-huggingface"
    fi
  else
      echo "config.json file not found."
  fi
fi

export ARGS="${CLI_ARGS} ${EXTRA_ARGS} ${AD_NO_HUGGINGFACE}"
export PYTHONPATH="${PYTHONPATH:-}:/usr/local/lib/python3.10/dist-packages/:${NAS_DIR}/python"
export SD_WEBUI_CACHE_FILE="/mnt/auto/sd/cache.json"
echo "args: $ARGS"

python ${ROOT}/webui.py --port 8000 --listen ${ARGS}
