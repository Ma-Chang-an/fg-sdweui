#!/bin/bash

set -Eeuox pipefail

bash /home/paas/mount.sh &

python webui.py --xformers --port 8000 --listen --skip-prepare-environment --no-download-sd-model --no-gradio-queue
